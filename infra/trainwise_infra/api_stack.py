from aws_cdk import CfnOutput, Duration, RemovalPolicy, Stack
from aws_cdk import aws_budgets as budgets
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_cloudwatch_actions as cloudwatch_actions
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as subscriptions
from aws_cdk import triggers
from constructs import Construct

# Secrets are created by hand as SSM SecureString parameters (CloudFormation cannot
# create SecureStrings). Each function reads only its own at cold start; see
# backend/lambda_handler.py and backend/migrate_handler.py.
API_SECRET_NAMES = ("DATABASE_URL",)
MIGRATE_SECRET_NAMES = ("DATABASE_URL_DIRECT",)
# Only the coach worker may read the AI provider's key.
COACH_SECRET_NAMES = ("DATABASE_URL", "ANTHROPIC_API_KEY")

# Coach calls in a day above which the alarm goes off: about 60 users' worth, far
# more than the test accounts make, so it catches a loop or abuse early.
COACH_DAILY_CALLS_ALARM = 300

# Monthly AWS spend (USD) the budget warns about: actual spend at 80%, forecast at 100%.
# The AI provider bills separately and is not included.
MONTHLY_BUDGET_USD = 10

# p95 duration (ms) of the API above which it is close to its 15 s timeout.
API_SLOW_P95_MS = 12_000


class ApiStack(Stack):
    """FastAPI backend on AWS Lambda behind a public Function URL."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        code: lambda_.Code,
        function_name: str,
        migrate_function_name: str,
        coach_function_name: str,
        frontend_urls: list[str],
        clerk_issuer: str,
        ssm_parameter_prefix: str,
        alarm_topic_name: str,
        alarm_email: str | None = None,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Every alarm, and the budget, notifies this topic. The address comes from the
        # deploy (a GitHub variable), so it stays out of the repository; AWS emails a
        # confirmation link first. Without one, the topic has no subscriber.
        self.alarm_topic = sns.Topic(self, "AlarmTopic", topic_name=alarm_topic_name)
        if alarm_email:
            self.alarm_topic.add_subscription(subscriptions.EmailSubscription(alarm_email))
        for service in ("cloudwatch.amazonaws.com", "budgets.amazonaws.com"):
            self.alarm_topic.add_to_resource_policy(
                iam.PolicyStatement(
                    actions=["sns:Publish"],
                    principals=[iam.ServicePrincipal(service)],
                    resources=[self.alarm_topic.topic_arn],
                    conditions={"StringEquals": {"aws:SourceAccount": self.account}},
                )
            )
        self._alarm_action = cloudwatch_actions.SnsAction(self.alarm_topic)

        log_group = logs.LogGroup(
            self,
            "ApiLogs",
            log_group_name=f"/aws/lambda/{function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # The AI coach worker: the API starts it without waiting (routers/coach.py), it
        # asks the model and stores the advice (coach_handler.py). Errors are stored on
        # the recommendation, so Lambda doesn't retry.
        coach_logs = logs.LogGroup(
            self,
            "CoachLogs",
            log_group_name=f"/aws/lambda/{coach_function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        self.coach_function = lambda_.Function(
            self,
            "CoachFunction",
            function_name=coach_function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            architecture=lambda_.Architecture.X86_64,
            handler="coach_handler.handler",
            code=code,
            memory_size=512,
            timeout=Duration.seconds(60),
            retry_attempts=0,
            max_event_age=Duration.hours(1),
            log_group=coach_logs,
            environment={"SSM_PARAMETER_PREFIX": ssm_parameter_prefix},
        )
        self.coach_function.add_to_role_policy(
            self._read_parameters(ssm_parameter_prefix, COACH_SECRET_NAMES)
        )
        self._alarm(
            "CoachErrorsAlarm",
            alarm_name=f"{coach_function_name}-errors",
            alarm_description="The coach worker failed (timeout or crash).",
            metric=self.coach_function.metric_errors(period=Duration.minutes(5)),
            threshold=1,
        )
        # The worker stores a failed answer instead of raising, so Errors misses an
        # outage at the provider. It logs one JSON line per run; count the failed ones.
        failed = logs.MetricFilter(
            self,
            "CoachFailedFilter",
            log_group=coach_logs,
            filter_pattern=logs.FilterPattern.string_value("$.status", "=", "failed"),
            metric_namespace="IronSage/Coach",
            metric_name="FailedAnswers",
            metric_value="1",
        )
        # The same line carries the tokens of each answer: AI usage per day, by metric.
        tokens = (("input_tokens", "InputTokens"), ("output_tokens", "OutputTokens"))
        for field, metric_name in tokens:
            logs.MetricFilter(
                self,
                f"Coach{metric_name}Filter",
                log_group=coach_logs,
                filter_pattern=logs.FilterPattern.number_value(f"$.{field}", ">=", 0),
                metric_namespace="IronSage/Coach",
                metric_name=metric_name,
                metric_value=f"$.{field}",
            )
        self._alarm(
            "CoachFailedAlarm",
            alarm_name=f"{coach_function_name}-failed-answers",
            alarm_description="Several coach answers failed in an hour (provider down?).",
            metric=failed.metric(period=Duration.hours(1), statistic="Sum"),
            threshold=5,
        )
        self._alarm(
            "CoachCallsAlarm",
            alarm_name=f"{coach_function_name}-daily-calls",
            alarm_description="Unusually many coach calls in a day: check costs.",
            metric=self.coach_function.metric_invocations(period=Duration.days(1)),
            threshold=COACH_DAILY_CALLS_ALARM,
        )

        self.function = lambda_.Function(
            self,
            "ApiFunction",
            function_name=function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            architecture=lambda_.Architecture.X86_64,
            handler="lambda_handler.handler",
            code=code,
            memory_size=512,
            timeout=Duration.seconds(15),
            log_group=log_group,
            environment={
                "FRONTEND_URL": ",".join(frontend_urls),
                "CLERK_ISSUER": clerk_issuer,
                "SSM_PARAMETER_PREFIX": ssm_parameter_prefix,
                "COACH_FUNCTION_NAME": coach_function_name,
            },
        )

        self.function.add_to_role_policy(
            self._read_parameters(ssm_parameter_prefix, API_SECRET_NAMES)
        )
        self.coach_function.grant_invoke(self.function)

        # FastAPI turns an unhandled exception into a 500 response, which Lambda's Errors
        # metric doesn't count; the Function URL's 5xx count includes those, crashes and
        # timeouts.
        self._alarm(
            "ApiServerErrorsAlarm",
            alarm_name=f"{function_name}-5xx",
            alarm_description="The API answered with 5xx errors (bug, crash or timeout).",
            metric=self.function.metric(
                "Url5xxCount", period=Duration.minutes(5), statistic="Sum"
            ),
            threshold=3,
        )
        self._alarm(
            "ApiThrottlesAlarm",
            alarm_name=f"{function_name}-throttles",
            alarm_description="API requests were throttled: concurrency limit reached.",
            metric=self.function.metric_throttles(period=Duration.minutes(5)),
            threshold=1,
        )
        self._alarm(
            "ApiSlowAlarm",
            alarm_name=f"{function_name}-slow",
            alarm_description="API p95 duration is close to its 15 s timeout.",
            metric=self.function.metric_duration(period=Duration.minutes(5), statistic="p95"),
            threshold=API_SLOW_P95_MS,
            evaluation_periods=3,
        )

        # Applies Alembic migrations during the deploy, before the API function is
        # updated. A failed migration fails the deploy, so the API keeps its old code.
        # It reruns whenever the code package changes; `alembic upgrade head` is a no-op
        # when there is nothing new.
        self.migrate_function = triggers.TriggerFunction(
            self,
            "MigrateFunction",
            function_name=migrate_function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            architecture=lambda_.Architecture.X86_64,
            handler="migrate_handler.handler",
            code=code,
            memory_size=512,
            timeout=Duration.minutes(5),
            log_group=logs.LogGroup(
                self,
                "MigrateLogs",
                log_group_name=f"/aws/lambda/{migrate_function_name}",
                retention=logs.RetentionDays.ONE_MONTH,
                removal_policy=RemovalPolicy.DESTROY,
            ),
            environment={"SSM_PARAMETER_PREFIX": ssm_parameter_prefix},
            execute_before=[self.function],
            execute_on_handler_change=True,
        )
        self.migrate_function.add_to_role_policy(
            self._read_parameters(ssm_parameter_prefix, MIGRATE_SECRET_NAMES)
        )
        # A failed migration also fails the deploy (and GitHub emails about that).
        self._alarm(
            "MigrateErrorsAlarm",
            alarm_name=f"{migrate_function_name}-errors",
            alarm_description="A database migration failed; the deploy kept the old API.",
            metric=self.migrate_function.metric_errors(period=Duration.minutes(5)),
            threshold=1,
        )

        # AWS spend for the whole account. Allowed in the simplified "projects" mode;
        # never turn on "advanced features" for it, that removes the project spend limit.
        budgets.CfnBudget(
            self,
            "MonthlyBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"{self.stack_name}-monthly-cost",
                budget_type="COST",
                time_unit="MONTHLY",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=MONTHLY_BUDGET_USD, unit="USD"
                ),
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type=kind,
                        comparison_operator="GREATER_THAN",
                        threshold=percent,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS", address=self.alarm_topic.topic_arn
                        )
                    ],
                )
                for kind, percent in (("ACTUAL", 80), ("FORECASTED", 100))
            ],
        )

        # CORS is handled by FastAPI, so the Function URL must not add its own headers.
        self.function_url = self.function.add_function_url(
            auth_type=lambda_.FunctionUrlAuthType.NONE,
        )

        CfnOutput(self, "FunctionName", value=self.function.function_name)
        CfnOutput(self, "FunctionUrl", value=self.function_url.url)

    def _alarm(
        self,
        construct_id: str,
        *,
        alarm_name: str,
        alarm_description: str,
        metric: cloudwatch.IMetric,
        threshold: float,
        evaluation_periods: int = 1,
    ) -> cloudwatch.Alarm:
        """An alarm that emails the alarm topic when it goes off and when it clears."""
        alarm = cloudwatch.Alarm(
            self,
            construct_id,
            alarm_name=alarm_name,
            alarm_description=alarm_description,
            metric=metric,
            threshold=threshold,
            evaluation_periods=evaluation_periods,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        alarm.add_alarm_action(self._alarm_action)
        alarm.add_ok_action(self._alarm_action)
        return alarm

    def _read_parameters(self, prefix: str, names: tuple[str, ...]) -> iam.PolicyStatement:
        return iam.PolicyStatement(
            actions=["ssm:GetParameters"],
            resources=[
                self.format_arn(
                    service="ssm",
                    resource="parameter",
                    resource_name=f"{prefix.strip('/')}/{name}",
                )
                for name in names
            ],
        )

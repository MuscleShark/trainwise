from aws_cdk import CfnOutput, Duration, RemovalPolicy, Stack
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
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
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

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
        cloudwatch.Alarm(
            self,
            "CoachErrorsAlarm",
            alarm_name=f"{coach_function_name}-errors",
            alarm_description="The coach worker failed (timeout or crash).",
            metric=self.coach_function.metric_errors(period=Duration.minutes(5)),
            threshold=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
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
        cloudwatch.Alarm(
            self,
            "CoachFailedAlarm",
            alarm_name=f"{coach_function_name}-failed-answers",
            alarm_description="Several coach answers failed in an hour (provider down?).",
            metric=failed.metric(period=Duration.hours(1), statistic="Sum"),
            threshold=5,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        cloudwatch.Alarm(
            self,
            "CoachCallsAlarm",
            alarm_name=f"{coach_function_name}-daily-calls",
            alarm_description="Unusually many coach calls in a day: check costs.",
            metric=self.coach_function.metric_invocations(period=Duration.days(1)),
            threshold=COACH_DAILY_CALLS_ALARM,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
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

        # CORS is handled by FastAPI, so the Function URL must not add its own headers.
        self.function_url = self.function.add_function_url(
            auth_type=lambda_.FunctionUrlAuthType.NONE,
        )

        CfnOutput(self, "FunctionName", value=self.function.function_name)
        CfnOutput(self, "FunctionUrl", value=self.function_url.url)

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

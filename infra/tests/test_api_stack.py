import json

import aws_cdk as cdk
import pytest
from aws_cdk import aws_lambda as lambda_
from aws_cdk.assertions import Match, Template

from trainwise_infra.api_stack import ApiStack


def synth(**kwargs) -> Template:
    app = cdk.App()
    stack = ApiStack(
        app,
        "TestApi",
        code=lambda_.Code.from_inline("def handler(event, context): pass"),
        function_name="trainwise-api-test",
        migrate_function_name="trainwise-migrate-test",
        coach_function_name="trainwise-coach-test",
        frontend_urls=["https://example.vercel.app", "http://localhost:3000"],
        clerk_issuer="https://test-instance.clerk.accounts.dev",
        ssm_parameter_prefix="/trainwise/test",
        alarm_topic_name="trainwise-alarms-test",
        env=cdk.Environment(account="123456789012", region="us-east-2"),
        **kwargs,
    )
    return Template.from_stack(stack)


@pytest.fixture(scope="module")
def template() -> Template:
    return synth(alarm_email="alerts@example.com")


def test_function_configuration(template):
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "trainwise-api-test",
            "Runtime": "python3.11",
            "Handler": "lambda_handler.handler",
            "MemorySize": 512,
            "Timeout": 15,
            "Architectures": ["x86_64"],
            "Environment": {
                "Variables": {
                    "FRONTEND_URL": "https://example.vercel.app,http://localhost:3000",
                    "CLERK_ISSUER": "https://test-instance.clerk.accounts.dev",
                    "SSM_PARAMETER_PREFIX": "/trainwise/test",
                    "COACH_FUNCTION_NAME": "trainwise-coach-test",
                }
            },
        },
    )


def test_coach_worker_configuration(template):
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "trainwise-coach-test",
            "Handler": "coach_handler.handler",
            "Timeout": 60,
            "Environment": {"Variables": {"SSM_PARAMETER_PREFIX": "/trainwise/test"}},
        },
    )
    # Errors are stored on the recommendation; Lambda must not run the request again.
    template.has_resource_properties(
        "AWS::Lambda::EventInvokeConfig", {"MaximumRetryAttempts": 0}
    )


def test_only_the_coach_worker_can_read_the_ai_key(template):
    coach = policy_for_function(template, "trainwise-coach-test")
    assert "parameter/trainwise/test/ANTHROPIC_API_KEY" in coach
    assert "parameter/trainwise/test/DATABASE_URL\"" in coach
    for other in ("trainwise-api-test", "trainwise-migrate-test"):
        assert "ANTHROPIC_API_KEY" not in policy_for_function(template, other)


def test_the_api_may_start_the_coach_worker(template):
    policy = policy_for_function(template, "trainwise-api-test")
    assert "lambda:InvokeFunction" in policy


def test_coach_alarms_watch_errors_and_daily_calls(template):
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {"AlarmName": "trainwise-coach-test-errors", "MetricName": "Errors", "Threshold": 1},
    )
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {"AlarmName": "trainwise-coach-test-daily-calls", "MetricName": "Invocations"},
    )
    template.has_resource_properties(
        "AWS::Logs::MetricFilter",
        {"FilterPattern": '{ $.status = "failed" }'},
    )
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {"AlarmName": "trainwise-coach-test-failed-answers", "MetricName": "FailedAnswers"},
    )


def test_secrets_are_not_in_environment(template):
    functions = template.find_resources("AWS::Lambda::Function")
    for function in functions.values():
        variables = function["Properties"].get("Environment", {}).get("Variables", {})
        assert "DATABASE_URL" not in variables
        assert "DATABASE_URL_DIRECT" not in variables
        assert "SECRET_KEY" not in variables
        assert "CLERK_SECRET_KEY" not in variables
        assert "ANTHROPIC_API_KEY" not in variables


def test_public_function_url_without_cors(template):
    template.has_resource_properties(
        "AWS::Lambda::Url",
        {"AuthType": "NONE", "Cors": Match.absent()},
    )


def policy_for_function(template: Template, function_name: str) -> str:
    functions = template.find_resources(
        "AWS::Lambda::Function", {"Properties": {"FunctionName": function_name}}
    )
    (function,) = functions.values()
    role_id = function["Properties"]["Role"]["Fn::GetAtt"][0]
    policies = template.find_resources("AWS::IAM::Policy")
    return json.dumps(
        [p for p in policies.values() if {"Ref": role_id} in p["Properties"]["Roles"]]
    )


def test_api_function_can_read_only_its_parameter(template):
    policy = policy_for_function(template, "trainwise-api-test")
    assert "parameter/trainwise/test/DATABASE_URL\"" in policy
    assert "DATABASE_URL_DIRECT" not in policy
    assert "parameter/trainwise/test/*" not in policy
    assert "SECRET_KEY" not in policy


def test_migrate_function_can_read_only_the_direct_url(template):
    policy = policy_for_function(template, "trainwise-migrate-test")
    assert "parameter/trainwise/test/DATABASE_URL_DIRECT" in policy
    assert "parameter/trainwise/test/DATABASE_URL\"" not in policy


def test_migrations_run_before_the_api_function_is_updated(template):
    template.has_resource_properties(
        "AWS::Lambda::Function",
        {
            "FunctionName": "trainwise-migrate-test",
            "Handler": "migrate_handler.handler",
            "Timeout": 300,
            "Environment": {"Variables": {"SSM_PARAMETER_PREFIX": "/trainwise/test"}},
        },
    )
    triggers = template.find_resources("Custom::Trigger")
    assert len(triggers) == 1
    (trigger_id,) = triggers
    api_functions = template.find_resources(
        "AWS::Lambda::Function", {"Properties": {"FunctionName": "trainwise-api-test"}}
    )
    (api_function,) = api_functions.values()
    assert trigger_id in api_function["DependsOn"]


def test_logs_are_kept_for_a_month(template):
    for name in ("trainwise-api-test", "trainwise-migrate-test"):
        template.has_resource_properties(
            "AWS::Logs::LogGroup",
            {"LogGroupName": f"/aws/lambda/{name}", "RetentionInDays": 30},
        )


ALARM_NAMES = (
    "trainwise-coach-test-errors",
    "trainwise-coach-test-failed-answers",
    "trainwise-coach-test-daily-calls",
    "trainwise-api-test-5xx",
    "trainwise-api-test-throttles",
    "trainwise-api-test-slow",
    "trainwise-migrate-test-errors",
)


def test_every_alarm_notifies_the_topic_when_it_goes_off_and_clears(template):
    (topic_id,) = template.find_resources(
        "AWS::SNS::Topic", {"Properties": {"TopicName": "trainwise-alarms-test"}}
    )
    alarms = template.find_resources("AWS::CloudWatch::Alarm")
    assert sorted(a["Properties"]["AlarmName"] for a in alarms.values()) == sorted(ALARM_NAMES)
    for alarm in alarms.values():
        assert alarm["Properties"]["AlarmActions"] == [{"Ref": topic_id}]
        assert alarm["Properties"]["OKActions"] == [{"Ref": topic_id}]


def test_alarm_email_is_subscribed_only_when_given(template):
    template.has_resource_properties(
        "AWS::SNS::Subscription", {"Protocol": "email", "Endpoint": "alerts@example.com"}
    )
    synth().resource_count_is("AWS::SNS::Subscription", 0)


def test_cloudwatch_and_budgets_may_publish_to_the_topic(template):
    (policy,) = template.find_resources("AWS::SNS::TopicPolicy").values()
    statements = policy["Properties"]["PolicyDocument"]["Statement"]
    services = sorted(s["Principal"]["Service"] for s in statements)
    assert services == ["budgets.amazonaws.com", "cloudwatch.amazonaws.com"]
    for statement in statements:
        assert statement["Action"] == "sns:Publish"
        assert statement["Condition"] == {
            "StringEquals": {"aws:SourceAccount": "123456789012"}
        }


def test_api_alarms_watch_5xx_throttles_and_slow_requests(template):
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {
            "AlarmName": "trainwise-api-test-5xx",
            "Namespace": "AWS/Lambda",
            "MetricName": "Url5xxCount",
            "Dimensions": [{"Name": "FunctionName", "Value": Match.any_value()}],
            "Statistic": "Sum",
            "Threshold": 3,
        },
    )
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {"AlarmName": "trainwise-api-test-throttles", "MetricName": "Throttles", "Threshold": 1},
    )
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {
            "AlarmName": "trainwise-api-test-slow",
            "MetricName": "Duration",
            "ExtendedStatistic": "p95",
            "Threshold": 12_000,
            "EvaluationPeriods": 3,
        },
    )
    template.has_resource_properties(
        "AWS::CloudWatch::Alarm",
        {"AlarmName": "trainwise-migrate-test-errors", "MetricName": "Errors"},
    )


def test_coach_tokens_are_counted_from_the_log_line(template):
    for field, metric_name in (("input_tokens", "InputTokens"), ("output_tokens", "OutputTokens")):
        template.has_resource_properties(
            "AWS::Logs::MetricFilter",
            {
                "FilterPattern": f"{{ $.{field} >= 0 }}",
                "MetricTransformations": [
                    {
                        "MetricNamespace": "IronSage/Coach",
                        "MetricName": metric_name,
                        "MetricValue": f"$.{field}",
                    }
                ],
            },
        )


def test_monthly_budget_notifies_the_topic(template):
    (topic_id,) = template.find_resources("AWS::SNS::Topic")
    template.has_resource_properties(
        "AWS::Budgets::Budget",
        {
            "Budget": {
                "BudgetType": "COST",
                "TimeUnit": "MONTHLY",
                "BudgetLimit": {"Amount": 10, "Unit": "USD"},
            },
            "NotificationsWithSubscribers": [
                {
                    "Notification": {"NotificationType": "ACTUAL", "Threshold": 80},
                    "Subscribers": [{"SubscriptionType": "SNS", "Address": {"Ref": topic_id}}],
                },
                {
                    "Notification": {"NotificationType": "FORECASTED", "Threshold": 100},
                    "Subscribers": [{"SubscriptionType": "SNS", "Address": {"Ref": topic_id}}],
                },
            ],
        },
    )

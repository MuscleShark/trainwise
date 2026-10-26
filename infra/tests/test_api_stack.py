import json

import aws_cdk as cdk
import pytest
from aws_cdk import aws_lambda as lambda_
from aws_cdk.assertions import Match, Template

from trainwise_infra.api_stack import ApiStack


@pytest.fixture(scope="module")
def template() -> Template:
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
        env=cdk.Environment(account="123456789012", region="us-east-2"),
    )
    return Template.from_stack(stack)


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

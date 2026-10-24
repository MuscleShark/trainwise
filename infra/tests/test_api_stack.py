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
                }
            },
        },
    )


def test_secrets_are_not_in_environment(template):
    functions = template.find_resources("AWS::Lambda::Function")
    for function in functions.values():
        variables = function["Properties"]["Environment"]["Variables"]
        assert "DATABASE_URL" not in variables
        assert "SECRET_KEY" not in variables
        assert "CLERK_SECRET_KEY" not in variables


def test_public_function_url_without_cors(template):
    template.has_resource_properties(
        "AWS::Lambda::Url",
        {"AuthType": "NONE", "Cors": Match.absent()},
    )


def test_function_can_read_only_its_parameters(template):
    policies = json.dumps(template.find_resources("AWS::IAM::Policy"))
    assert "ssm:GetParameters" in policies
    assert "parameter/trainwise/test/DATABASE_URL" in policies
    assert "parameter/trainwise/test/*" not in policies
    assert "SECRET_KEY" not in policies


def test_logs_are_kept_for_a_month(template):
    template.has_resource_properties(
        "AWS::Logs::LogGroup",
        {"LogGroupName": "/aws/lambda/trainwise-api-test", "RetentionInDays": 30},
    )

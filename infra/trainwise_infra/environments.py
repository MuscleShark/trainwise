"""The deployed environments: one ApiStack each, from the settings in cdk.json."""

from collections.abc import Callable

import aws_cdk as cdk
from aws_cdk import aws_lambda as lambda_

from trainwise_infra.api_stack import ApiStack

# Merges to main deploy staging; production is promoted by hand (docs/deployment.md).
ENVIRONMENTS = ("production", "staging")


def add_stacks(app: cdk.App, code: Callable[[], lambda_.Code]) -> dict[str, ApiStack]:
    """Adds a stack per environment. The production stack keeps its original id
    (TrainWiseApi) and resource names, so CloudFormation never replaces it. `code` makes
    the Lambda package: an asset belongs to one stack, so each stack gets its own."""
    environments = app.node.get_context("environments")
    env = cdk.Environment(
        account=app.node.get_context("account"),
        region=app.node.get_context("region"),
    )
    # Set by the deploy workflow from the GitHub environment's variable ALARM_EMAIL (not
    # in the repo). A deploy names one stack, so the address is that environment's.
    alarm_email = app.node.try_get_context("alarmEmail") or None
    stacks = {}
    for name in ENVIRONMENTS:
        settings = environments[name]
        stacks[name] = ApiStack(
            app,
            settings["stackName"],
            code=code(),
            function_name=settings["functionName"],
            migrate_function_name=settings["migrateFunctionName"],
            coach_function_name=settings["coachFunctionName"],
            frontend_urls=settings["frontendUrls"],
            clerk_issuer=app.node.get_context("clerkIssuer"),
            ssm_parameter_prefix=settings["ssmParameterPrefix"],
            alarm_topic_name=settings["alarmTopicName"],
            metric_namespace=settings["metricNamespace"],
            monthly_budget=settings["monthlyBudget"],
            alarm_email=alarm_email,
            env=env,
        )
    return stacks

import json
import re
from pathlib import Path

import aws_cdk as cdk
import pytest
from aws_cdk import aws_lambda as lambda_
from aws_cdk.assertions import Template

from trainwise_infra.environments import add_stacks

CDK_JSON = Path(__file__).resolve().parent.parent / "cdk.json"

# Production's stack id and resource names as first deployed. Changing one would make
# CloudFormation replace the resource (or the whole stack), so they are pinned here.
PRODUCTION = {
    "stackName": "TrainWiseApi",
    "functionName": "trainwise-api-prod",
    "migrateFunctionName": "trainwise-migrate-prod",
    "coachFunctionName": "trainwise-coach-prod",
    "alarmTopicName": "trainwise-alarms-prod",
    "metricNamespace": "IronSage/Coach",
    "ssmParameterPrefix": "/trainwise/prod",
}


@pytest.fixture(scope="module")
def context() -> dict:
    return json.loads(CDK_JSON.read_text())["context"]


@pytest.fixture(scope="module")
def templates(context) -> dict[str, Template]:
    app = cdk.App(context=context)
    stacks = add_stacks(app, lambda: lambda_.Code.from_inline("def handler(event, context): pass"))
    return {name: Template.from_stack(stack) for name, stack in stacks.items()}


def test_production_keeps_its_stack_and_resource_names(context, templates):
    production = context["environments"]["production"]
    assert {key: production[key] for key in PRODUCTION} == PRODUCTION
    assert production["frontendUrls"] == ["https://ironsage.app", "https://www.ironsage.app"]
    templates["production"].has_resource_properties(
        "AWS::Lambda::Function", {"FunctionName": "trainwise-api-prod"}
    )


def test_two_stacks_from_the_same_code(templates):
    for name in ("production", "staging"):
        functions = templates[name].find_resources("AWS::Lambda::Function").values()
        handlers = {f["Properties"].get("Handler") for f in functions}
        assert {"lambda_handler.handler", "migrate_handler.handler", "coach_handler.handler"} <= handlers


def named_resources(template: Template) -> set[str]:
    """Every physical name the stack sets."""
    keys = ("FunctionName", "TopicName", "LogGroupName", "AlarmName", "Name")
    return {
        resource["Properties"][key]
        for resource in template.to_json()["Resources"].values()
        for key in keys
        if isinstance(resource.get("Properties", {}).get(key), str)
    }


def test_staging_shares_no_name_or_secret_with_production(templates):
    production = named_resources(templates["production"])
    staging = named_resources(templates["staging"])
    assert production and staging
    assert production.isdisjoint(staging)
    staging_policies = json.dumps(templates["staging"].find_resources("AWS::IAM::Policy"))
    assert "parameter/trainwise/staging/DATABASE_URL" in staging_policies
    assert "/trainwise/prod" not in staging_policies
    assert "IronSage/Coach\"" not in json.dumps(templates["staging"].to_json())


def test_only_production_has_the_account_budget(templates):
    templates["production"].resource_count_is("AWS::Budgets::Budget", 1)
    templates["staging"].resource_count_is("AWS::Budgets::Budget", 0)


def test_production_keeps_every_logical_id(templates):
    # Production's resources as deployed from main before staging existed (logical id →
    # type). A new or renamed id is a new resource, and the old one would be deleted.
    # The migrate trigger's Lambda version ends in a hash of the code, new on every deploy.
    expected = json.loads((Path(__file__).parent / "production_resources.json").read_text())
    resources = templates["production"].to_json()["Resources"]
    actual = {
        re.sub(r"(CurrentVersion[0-9A-F]{8})[0-9a-f]{32}$", r"\1", k): v["Type"]
        for k, v in resources.items()
        if v["Type"] != "AWS::CDK::Metadata"
    }
    assert actual == expected

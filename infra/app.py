from pathlib import Path

import aws_cdk as cdk
from aws_cdk import aws_lambda as lambda_

from trainwise_infra.api_stack import ApiStack

# Built by backend/scripts/build_lambda.sh before `cdk synth` / `cdk deploy`.
LAMBDA_PACKAGE = Path(__file__).resolve().parent.parent / "backend" / "build" / "package"

app = cdk.App()

if not (LAMBDA_PACKAGE / "lambda_handler.py").exists() or not (LAMBDA_PACKAGE / "alembic.ini").exists():
    raise SystemExit(
        f"Lambda package not found at {LAMBDA_PACKAGE}. Run backend/scripts/build_lambda.sh first."
    )

ApiStack(
    app,
    "TrainWiseApi",
    code=lambda_.Code.from_asset(str(LAMBDA_PACKAGE)),
    function_name=app.node.get_context("functionName"),
    migrate_function_name=app.node.get_context("migrateFunctionName"),
    frontend_urls=app.node.get_context("frontendUrls"),
    clerk_issuer=app.node.get_context("clerkIssuer"),
    ssm_parameter_prefix=app.node.get_context("ssmParameterPrefix"),
    env=cdk.Environment(
        account=app.node.get_context("account"),
        region=app.node.get_context("region"),
    ),
)

app.synth()

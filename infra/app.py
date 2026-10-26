from pathlib import Path

import aws_cdk as cdk
from aws_cdk import aws_lambda as lambda_

from trainwise_infra.environments import add_stacks

# Built by backend/scripts/build_lambda.sh before `cdk synth` / `cdk deploy`.
LAMBDA_PACKAGE = Path(__file__).resolve().parent.parent / "backend" / "build" / "package"

app = cdk.App()

if not (LAMBDA_PACKAGE / "lambda_handler.py").exists() or not (LAMBDA_PACKAGE / "alembic.ini").exists():
    raise SystemExit(
        f"Lambda package not found at {LAMBDA_PACKAGE}. Run backend/scripts/build_lambda.sh first."
    )

add_stacks(app, lambda: lambda_.Code.from_asset(str(LAMBDA_PACKAGE)))

app.synth()

"""AWS Lambda entry point (function handler: "lambda_handler.handler").

When SSM_PARAMETER_PREFIX is set, DATABASE_URL and SECRET_KEY are read from SSM
Parameter Store (SecureString) at cold start, before the app modules that need them
are imported.
"""

import os

SECRET_NAMES = ("DATABASE_URL", "SECRET_KEY")


def load_ssm_parameters(prefix: str | None, ssm_client=None) -> None:
    if not prefix:
        return

    if ssm_client is None:
        import boto3  # bundled with the Lambda Python runtime

        ssm_client = boto3.client("ssm")

    prefix = prefix.rstrip("/")
    response = ssm_client.get_parameters(
        Names=[f"{prefix}/{name}" for name in SECRET_NAMES],
        WithDecryption=True,
    )
    if response["InvalidParameters"]:
        raise RuntimeError(f"Missing SSM parameters: {response['InvalidParameters']}")

    for parameter in response["Parameters"]:
        os.environ[parameter["Name"].rsplit("/", 1)[1]] = parameter["Value"]


load_ssm_parameters(os.getenv("SSM_PARAMETER_PREFIX"))

from mangum import Mangum  # noqa: E402

from main import app  # noqa: E402

handler = Mangum(app, lifespan="off")

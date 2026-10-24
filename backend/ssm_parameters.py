"""Reads secrets from SSM Parameter Store (SecureString) into environment variables."""

import os


def load_ssm_parameters(prefix: str | None, names: tuple[str, ...], ssm_client=None) -> None:
    if not prefix:
        return

    if ssm_client is None:
        import boto3  # bundled with the Lambda Python runtime

        ssm_client = boto3.client("ssm")

    prefix = prefix.rstrip("/")
    response = ssm_client.get_parameters(
        Names=[f"{prefix}/{name}" for name in names],
        WithDecryption=True,
    )
    if response["InvalidParameters"]:
        raise RuntimeError(f"Missing SSM parameters: {response['InvalidParameters']}")

    for parameter in response["Parameters"]:
        os.environ[parameter["Name"].rsplit("/", 1)[1]] = parameter["Value"]

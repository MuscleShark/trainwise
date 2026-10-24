from aws_cdk import CfnOutput, Duration, RemovalPolicy, Stack
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from constructs import Construct

# Secrets are created by hand as SSM SecureString parameters (CloudFormation cannot
# create SecureStrings). The function reads them at cold start; see backend/lambda_handler.py.
SECRET_PARAMETER_NAMES = ("DATABASE_URL",)


class ApiStack(Stack):
    """FastAPI backend on AWS Lambda behind a public Function URL."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        code: lambda_.Code,
        function_name: str,
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
            },
        )

        self.function.add_to_role_policy(
            iam.PolicyStatement(
                actions=["ssm:GetParameters"],
                resources=[
                    self.format_arn(
                        service="ssm",
                        resource="parameter",
                        resource_name=f"{ssm_parameter_prefix.strip('/')}/{name}",
                    )
                    for name in SECRET_PARAMETER_NAMES
                ],
            )
        )

        # CORS is handled by FastAPI, so the Function URL must not add its own headers.
        self.function_url = self.function.add_function_url(
            auth_type=lambda_.FunctionUrlAuthType.NONE,
        )

        CfnOutput(self, "FunctionName", value=self.function.function_name)
        CfnOutput(self, "FunctionUrl", value=self.function_url.url)

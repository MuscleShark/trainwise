from aws_cdk import CfnOutput, Duration, RemovalPolicy, Stack
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import triggers
from constructs import Construct

# Secrets are created by hand as SSM SecureString parameters (CloudFormation cannot
# create SecureStrings). Each function reads only its own at cold start; see
# backend/lambda_handler.py and backend/migrate_handler.py.
API_SECRET_NAMES = ("DATABASE_URL",)
MIGRATE_SECRET_NAMES = ("DATABASE_URL_DIRECT",)


class ApiStack(Stack):
    """FastAPI backend on AWS Lambda behind a public Function URL."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        code: lambda_.Code,
        function_name: str,
        migrate_function_name: str,
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
            self._read_parameters(ssm_parameter_prefix, API_SECRET_NAMES)
        )

        # Applies Alembic migrations during the deploy, before the API function is
        # updated. A failed migration fails the deploy, so the API keeps its old code.
        # It reruns whenever the code package changes; `alembic upgrade head` is a no-op
        # when there is nothing new.
        self.migrate_function = triggers.TriggerFunction(
            self,
            "MigrateFunction",
            function_name=migrate_function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            architecture=lambda_.Architecture.X86_64,
            handler="migrate_handler.handler",
            code=code,
            memory_size=512,
            timeout=Duration.minutes(5),
            log_group=logs.LogGroup(
                self,
                "MigrateLogs",
                log_group_name=f"/aws/lambda/{migrate_function_name}",
                retention=logs.RetentionDays.ONE_MONTH,
                removal_policy=RemovalPolicy.DESTROY,
            ),
            environment={"SSM_PARAMETER_PREFIX": ssm_parameter_prefix},
            execute_before=[self.function],
            execute_on_handler_change=True,
        )
        self.migrate_function.add_to_role_policy(
            self._read_parameters(ssm_parameter_prefix, MIGRATE_SECRET_NAMES)
        )

        # CORS is handled by FastAPI, so the Function URL must not add its own headers.
        self.function_url = self.function.add_function_url(
            auth_type=lambda_.FunctionUrlAuthType.NONE,
        )

        CfnOutput(self, "FunctionName", value=self.function.function_name)
        CfnOutput(self, "FunctionUrl", value=self.function_url.url)

    def _read_parameters(self, prefix: str, names: tuple[str, ...]) -> iam.PolicyStatement:
        return iam.PolicyStatement(
            actions=["ssm:GetParameters"],
            resources=[
                self.format_arn(
                    service="ssm",
                    resource="parameter",
                    resource_name=f"{prefix.strip('/')}/{name}",
                )
                for name in names
            ],
        )

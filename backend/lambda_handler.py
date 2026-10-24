"""AWS Lambda entry point (function handler: "lambda_handler.handler").

When SSM_PARAMETER_PREFIX is set, DATABASE_URL is read from SSM Parameter Store
(SecureString) at cold start, before the app modules that need it are imported.
"""

import os

from ssm_parameters import load_ssm_parameters

load_ssm_parameters(os.getenv("SSM_PARAMETER_PREFIX"), ("DATABASE_URL",))

from mangum import Mangum  # noqa: E402

from main import app  # noqa: E402

handler = Mangum(app, lifespan="off")

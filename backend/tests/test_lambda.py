from main import handler


def function_url_event(path: str, method: str = "GET", headers: dict | None = None) -> dict:
    """Minimal Lambda Function URL (payload v2.0) event."""
    return {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": path,
        "rawQueryString": "",
        "headers": {"host": "example.lambda-url.us-east-1.on.aws", **(headers or {})},
        "requestContext": {
            "http": {
                "method": method,
                "path": path,
                "protocol": "HTTP/1.1",
                "sourceIp": "127.0.0.1",
                "userAgent": "pytest",
            },
            "stage": "$default",
        },
        "isBase64Encoded": False,
    }


def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_lambda_handler_serves_requests(client):
    response = handler(function_url_event("/health"), None)
    assert response["statusCode"] == 200
    assert response["body"] == '{"status":"ok"}'


def test_lambda_handler_applies_cors(client):
    response = handler(
        function_url_event(
            "/workouts",
            method="OPTIONS",
            headers={
                "origin": "http://localhost:3000",
                "access-control-request-method": "GET",
            },
        ),
        None,
    )
    assert response["statusCode"] == 200
    assert response["headers"]["access-control-allow-origin"] == "http://localhost:3000"

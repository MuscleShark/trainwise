import os

import pytest

from lambda_handler import load_ssm_parameters


class FakeSSM:
    def __init__(self, parameters: dict[str, str]):
        self.parameters = parameters
        self.calls = []

    def get_parameters(self, Names, WithDecryption):
        self.calls.append((Names, WithDecryption))
        return {
            "Parameters": [
                {"Name": name, "Value": self.parameters[name]}
                for name in Names
                if name in self.parameters
            ],
            "InvalidParameters": [name for name in Names if name not in self.parameters],
        }


@pytest.fixture
def restore_env(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", os.environ.get("DATABASE_URL", ""))


def test_no_prefix_does_nothing():
    ssm = FakeSSM({})
    load_ssm_parameters(None, ssm)
    assert ssm.calls == []


def test_loads_secrets_into_environment(restore_env):
    ssm = FakeSSM({"/trainwise/prod/DATABASE_URL": "postgresql+psycopg://from-ssm"})

    load_ssm_parameters("/trainwise/prod/", ssm)

    assert ssm.calls == [(["/trainwise/prod/DATABASE_URL"], True)]
    assert os.environ["DATABASE_URL"] == "postgresql+psycopg://from-ssm"


def test_missing_parameter_fails_fast(restore_env):
    ssm = FakeSSM({})

    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        load_ssm_parameters("/trainwise/prod", ssm)

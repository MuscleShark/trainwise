#!/usr/bin/env bash
# Builds the Lambda deployment package into backend/build/package.
# Dependencies are fetched as manylinux x86_64 wheels so this works from macOS too.
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf build/package
mkdir -p build/package

python3 -m pip install \
  --quiet \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.11 \
  --only-binary=:all: \
  --target build/package \
  -r requirements.txt

cp ./*.py build/package/
cp -r routers migrations coach build/package/
cp alembic.ini build/package/
find build/package -name "__pycache__" -type d -prune -exec rm -rf {} +

du -sh build/package

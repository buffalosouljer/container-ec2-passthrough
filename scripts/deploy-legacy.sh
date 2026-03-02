#!/bin/bash
set -euo pipefail

# Phase 1: Legacy Deployment with Static Access Keys
# This script builds and launches containers using static IAM credentials.
# Required environment variables (set by user_data or manually):
#   S3_ACCESS_KEY, S3_SECRET_KEY, S3_BUCKET
#   DDB_ACCESS_KEY, DDB_SECRET_KEY, DYNAMODB_TABLE
#   KMS_ACCESS_KEY, KMS_SECRET_KEY, KMS_KEY_ID
#   REGION

echo "=== Legacy Deployment (Static Access Keys) ==="

REGION="${REGION:-us-east-1}"
CONTAINER_DIR="${CONTAINER_DIR:-$HOME/containers}"

# Validate required environment variables
for var in S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET \
           DDB_ACCESS_KEY DDB_SECRET_KEY DYNAMODB_TABLE \
           KMS_ACCESS_KEY KMS_SECRET_KEY KMS_KEY_ID; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Required environment variable $var is not set"
    exit 1
  fi
done

# Stop and remove existing containers
echo "Stopping existing containers..."
podman stop container-a container-b container-c 2>/dev/null || true
podman rm container-a container-b container-c 2>/dev/null || true

# Build container images
echo "Building container images..."
podman build -t container-a:latest "$CONTAINER_DIR/container-a/"
podman build -t container-b:latest "$CONTAINER_DIR/container-b/"
podman build -t container-c:latest "$CONTAINER_DIR/container-c/"

# Launch Container A (S3)
echo "Launching Container A (S3 workload)..."
podman run -d \
  -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" \
  -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e S3_BUCKET="$S3_BUCKET" \
  --name container-a \
  container-a:latest

# Launch Container B (DynamoDB)
echo "Launching Container B (DynamoDB workload)..."
podman run -d \
  -e AWS_ACCESS_KEY_ID="$DDB_ACCESS_KEY" \
  -e AWS_SECRET_ACCESS_KEY="$DDB_SECRET_KEY" \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e DYNAMODB_TABLE="$DYNAMODB_TABLE" \
  --name container-b \
  container-b:latest

# Launch Container C (KMS)
echo "Launching Container C (KMS workload)..."
podman run -d \
  -e AWS_ACCESS_KEY_ID="$KMS_ACCESS_KEY" \
  -e AWS_SECRET_ACCESS_KEY="$KMS_SECRET_KEY" \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e KMS_KEY_ID="$KMS_KEY_ID" \
  --name container-c \
  container-c:latest

echo ""
echo "=== Container Status ==="
podman ps -a

echo ""
echo "=== Waiting 35 seconds for first operations... ==="
sleep 35

echo ""
echo "=== Container A Logs ==="
podman logs container-a

echo ""
echo "=== Container B Logs ==="
podman logs container-b

echo ""
echo "=== Container C Logs ==="
podman logs container-c

echo ""
echo "=== Legacy deployment complete ==="

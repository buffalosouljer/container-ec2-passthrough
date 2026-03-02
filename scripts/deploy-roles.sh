#!/bin/bash
set -euo pipefail

# Phase 2: Role-Based Deployment (IMDS + AWS Config Profiles)
# This script builds and launches containers using IMDS role assumption.
# No static access keys are used.
#
# Required environment variables:
#   CONTAINER_A_ROLE_ARN, CONTAINER_B_ROLE_ARN, CONTAINER_C_ROLE_ARN
#   S3_BUCKET, DYNAMODB_TABLE, KMS_KEY_ID
#   REGION

echo "=== Role-Based Deployment (IMDS + AWS Config Profiles) ==="

REGION="${REGION:-us-east-1}"
CONTAINER_DIR="${CONTAINER_DIR:-$HOME/containers}"
AWS_CONFIGS_DIR="${AWS_CONFIGS_DIR:-$HOME/aws-configs}"

# Validate required environment variables
for var in CONTAINER_A_ROLE_ARN CONTAINER_B_ROLE_ARN CONTAINER_C_ROLE_ARN \
           S3_BUCKET DYNAMODB_TABLE KMS_KEY_ID; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: Required environment variable $var is not set"
    exit 1
  fi
done

# Step 1: Stop and remove existing containers
echo "Stopping existing containers..."
podman stop container-a container-b container-c 2>/dev/null || true
podman rm container-a container-b container-c 2>/dev/null || true

# Step 2: Verify pasta networking
echo "Verifying network backend..."
NETWORK_BACKEND=$(podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null || echo "unknown")
echo "Network backend: $NETWORK_BACKEND"

# Step 3: Verify IMDS reachability
echo "Verifying IMDS reachability..."
IMDS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "failed")
if [ "$IMDS_STATUS" = "200" ]; then
  echo "IMDS reachable (HTTP $IMDS_STATUS)"
else
  echo "WARNING: IMDS returned HTTP $IMDS_STATUS (expected 200)"
fi

# Step 4: Create AWS config files with actual role ARNs
echo "Creating AWS config files..."
mkdir -p "$AWS_CONFIGS_DIR"

cat > "$AWS_CONFIGS_DIR/container-a-config" << EOF
[profile container-role]
role_arn = $CONTAINER_A_ROLE_ARN
credential_source = Ec2InstanceMetadata
region = $REGION
EOF

cat > "$AWS_CONFIGS_DIR/container-b-config" << EOF
[profile container-role]
role_arn = $CONTAINER_B_ROLE_ARN
credential_source = Ec2InstanceMetadata
region = $REGION
EOF

cat > "$AWS_CONFIGS_DIR/container-c-config" << EOF
[profile container-role]
role_arn = $CONTAINER_C_ROLE_ARN
credential_source = Ec2InstanceMetadata
region = $REGION
EOF

# Step 5: Build container images
echo "Building container images..."
podman build -t container-a:latest "$CONTAINER_DIR/container-a/"
podman build -t container-b:latest "$CONTAINER_DIR/container-b/"
podman build -t container-c:latest "$CONTAINER_DIR/container-c/"

# Step 6: Launch containers with AWS config mount + profile
echo "Launching Container A (S3 workload with role assumption)..."
podman run -d \
  --network pasta \
  -v "$AWS_CONFIGS_DIR/container-a-config:/home/app/.aws/config:ro,z" \
  -e AWS_PROFILE=container-role \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e S3_BUCKET="$S3_BUCKET" \
  --name container-a \
  container-a:latest

echo "Launching Container B (DynamoDB workload with role assumption)..."
podman run -d \
  --network pasta \
  -v "$AWS_CONFIGS_DIR/container-b-config:/home/app/.aws/config:ro,z" \
  -e AWS_PROFILE=container-role \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e DYNAMODB_TABLE="$DYNAMODB_TABLE" \
  --name container-b \
  container-b:latest

echo "Launching Container C (KMS workload with role assumption)..."
podman run -d \
  --network pasta \
  -v "$AWS_CONFIGS_DIR/container-c-config:/home/app/.aws/config:ro,z" \
  -e AWS_PROFILE=container-role \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e KMS_KEY_ID="$KMS_KEY_ID" \
  --name container-c \
  container-c:latest

echo ""
echo "=== Container Status ==="
podman ps -a

# Step 7: Health check
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

# Step 8: Verify no access keys on disk
echo ""
echo "=== Verifying no static access keys on instance ==="
FOUND_KEYS=$(find "$HOME" -name "credentials" -o -name ".env" 2>/dev/null | xargs grep -l "AKIA" 2>/dev/null || true)
if [ -z "$FOUND_KEYS" ]; then
  echo "PASS: No static access keys found on disk"
else
  echo "FAIL: Static access keys found in: $FOUND_KEYS"
fi

# Step 9: Verify IMDS access from container
echo ""
echo "=== Verifying IMDS access from Container A ==="
podman exec container-a curl -s -w "\n%{http_code}" \
  -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "IMDS check from container failed (curl may not be installed in container)"

echo ""
echo "=== Role-based deployment complete ==="

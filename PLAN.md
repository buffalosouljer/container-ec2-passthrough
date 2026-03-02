# KMS Role-Based Access: Eliminating Static Access Keys from Podman Containers

## Solution Overview

Replace static AWS access keys in Podman containers with IAM role assumption via EC2 instance metadata (IMDS). Each container assumes its own scoped IAM role — no credential vending service, no custom code, no key rotation.

This project is structured as a **live demo**: Phase 1 shows the insecure "before" state (static keys baked into containers), then Phase 2 performs the migration to IMDS-based role assumption in front of the audience.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  EC2 Instance (Fedora 41, Podman 5.x, IMDSv2 hop_limit=2)         │
│  Instance Profile: base-instance-role                               │
│    └─ sts:AssumeRole for role-a, role-b, role-c                     │
│                                                                     │
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐    │
│  │ Container A      │ │ Container B      │ │ Container C      │    │
│  │ (S3 workload)    │ │ (DynamoDB wkld)  │ │ (KMS workload)   │    │
│  │                  │ │                  │ │                  │    │
│  │ AWS_PROFILE=     │ │ AWS_PROFILE=     │ │ AWS_PROFILE=     │    │
│  │   container-role │ │   container-role │ │   container-role │    │
│  │                  │ │                  │ │                  │    │
│  │ ~/.aws/config:   │ │ ~/.aws/config:   │ │ ~/.aws/config:   │    │
│  │ role_arn=role-a  │ │ role_arn=role-b  │ │ role_arn=role-c  │    │
│  │ credential_src=  │ │ credential_src=  │ │ credential_src=  │    │
│  │ Ec2InstanceMeta  │ │ Ec2InstanceMeta  │ │ Ec2InstanceMeta  │    │
│  └────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘    │
│           │                    │                    │               │
│           └────────────────────┼────────────────────┘               │
│                                │                                    │
│                    pasta networking (rootless)                       │
│                                │                                    │
│                    ┌───────────▼───────────┐                        │
│                    │ IMDS 169.254.169.254  │                        │
│                    │ (hop_limit = 2)       │                        │
│                    └───────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

### How the SDK Credential Chain Works (no code changes)

1. Container starts with `AWS_PROFILE=container-role`
2. SDK reads `~/.aws/config`, finds `credential_source = Ec2InstanceMetadata`
3. SDK calls IMDS (169.254.169.254) → gets instance profile temp creds (auto-refreshing)
4. SDK sees `role_arn`, calls `sts:AssumeRole` using instance profile creds
5. SDK caches and auto-refreshes the assumed role creds before expiry
6. Application uses the assumed role creds transparently — zero key management

### Why This Beats the Credential Vending Service

| Factor                     | Vending Service          | IMDS + AWS Config Profiles |
|---------------------------|--------------------------|----------------------------|
| Custom code to write      | ~80 lines (HTTP server)  | 0                          |
| Infrastructure to maintain| systemd service on host   | None                       |
| SDK auto-refresh          | No (manual rotation)     | Yes (built-in)             |
| Code changes in apps      | Yes (new credential flow) | No (set env var only)      |
| Estimated effort          | 10-20 hours              | 4-8 hours                  |

---

## Current Status

### Phase 1: COMPLETE — deployed and validated
- Instance: Fedora 41 on t3.micro (Free Tier)
- AMI: `ami-09722669c73b517f6` (Fedora 41 Cloud Base, us-east-1)
- Key pair: `container-roles-demo` (stored at `~/.ssh/container-roles-demo.pem`)
- All 3 containers running with static access keys baked into env vars
- S3, DynamoDB, and KMS operations succeeding every 30 seconds

### Phase 2: PRE-STAGED — ready to run
- IAM roles created (container_a_s3, container_b_dynamodb, container_c_kms)
- Instance profile attached with sts:AssumeRole permissions
- IMDSv2 enabled with hop_limit=2
- `deploy-roles.sh` and AWS config files already on the instance
- SELinux volume mount fix (`:ro,z`) already applied

### Makefile: COMPLETE — switch between phases with one command
```bash
cd ~/projects/contianer-with-roles-demo
make help      # show all targets
make phase1    # revert to static access keys
make phase2    # migrate to IMDS role assumption
make status    # show running containers
make logs      # show recent logs
make keys      # show credential env vars
make ssh       # interactive SSH session
```

---

## Demo Practice Flow

```bash
# 1. Show the "before" state
make status    # 3 containers running
make keys      # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY visible in plain text
make logs      # operations succeeding with static keys

# 2. Perform the migration (Phase 2)
make phase2    # stops containers, relaunches with IMDS role assumption

# 3. Show the "after" state
make keys      # only AWS_PROFILE=container-role, NO access keys
make logs      # operations STILL succeeding — no code changes needed

# 4. Reset for another run
make phase1    # back to static keys for another demo
```

---

## Phase 1: Build the Simulated Existing Environment

**Goal:** Stand up the current-state architecture — 1 EC2 instance running 3 rootless
Podman containers, each using static access keys to access different AWS services.

### 1.1 — Terraform: Core Infrastructure

```
infra/
├── main.tf              # Provider (aws ~> 5.0), data sources (caller_identity)
├── variables.tf         # Region, project name, key pair, instance type, SSH CIDR
├── terraform.tfvars     # us-east-1, container-roles-demo, t3.micro
├── vpc.tf               # VPC (10.0.0.0/16), public subnet, IGW, route table
├── security_group.tf    # SG: SSH ingress + all egress
├── ec2.tf               # Fedora 41 EC2 with instance profile, IMDSv2, gzipped user_data
├── iam_legacy.tf        # 3 IAM users with static access keys
├── iam_policies.tf      # Scoped policies for each user (S3, DynamoDB, KMS)
├── iam_roles.tf         # Phase 2 roles (pre-created)
├── iam_instance_profile.tf # Instance base role with sts:AssumeRole
├── kms.tf               # KMS key (policy allows both legacy user AND container role)
├── dynamodb.tf          # DynamoDB table (pk/sk, PAY_PER_REQUEST)
├── s3.tf                # S3 bucket with versioning and public access block
└── outputs.tf           # Instance IP/ID, resource ARNs, access keys (sensitive), role ARNs
```

**IAM users (simulating legacy access keys):**

| User              | Permissions                        | Container |
|-------------------|------------------------------------|-----------|
| `legacy-s3-user`  | s3:GetObject, s3:PutObject on bucket | A         |
| `legacy-ddb-user` | dynamodb:GetItem, dynamodb:PutItem, dynamodb:Query on table | B |
| `legacy-kms-user` | kms:Encrypt, kms:Decrypt on key    | C         |

### 1.2 — EC2 Bootstrap (user_data.sh.tftpl)

The user_data template is gzipped via `base64gzip()` (required — uncompressed exceeds
the 16KB user_data limit). It:

1. Installs `podman`, `passt`, `python3-pip`, `curl` via `dnf` (Fedora 41)
2. Creates `appuser` with lingering enabled for rootless containers
3. Writes all 3 container Dockerfiles and app.py files
4. Writes `deploy-legacy.sh` with static access keys baked in from Terraform
5. Pre-stages `deploy-roles.sh` for Phase 2 migration
6. Pre-stages AWS config files for Phase 2 (in `~/aws-configs/`)
7. Writes `.env` file with resource names (bucket, table, KMS key)
8. Executes `deploy-legacy.sh` as appuser (Phase 1 active by default)

### 1.3 — Container Workloads

Each container is a Python script using boto3, performing AWS operations every 30 seconds.

```
containers/           # Local reference copies (actual code is in user_data template)
├── container-a/
│   ├── Dockerfile    # python:3.12-slim + boto3
│   └── app.py        # S3 PutObject/GetObject
├── container-b/
│   ├── Dockerfile
│   └── app.py        # DynamoDB PutItem/GetItem
└── container-c/
    ├── Dockerfile
    └── app.py        # KMS Encrypt/Decrypt
```

Phase 1 container launch (static keys via env vars):
```bash
podman run -d \
  -e AWS_ACCESS_KEY_ID=<key> \
  -e AWS_SECRET_ACCESS_KEY=<secret> \
  -e AWS_DEFAULT_REGION=us-east-1 \
  --name container-a \
  container-a:latest
```

### 1.4 — Validation (Phase 1) — COMPLETE

- [x] `podman ps` shows 3 running containers under `appuser`
- [x] Container A logs show successful S3 put/get operations
- [x] Container B logs show successful DynamoDB put/get operations
- [x] Container C logs show successful KMS encrypt/decrypt operations
- [x] All operations use static access keys (visible via `make keys`)

---

## Phase 2: Implement IMDS-Based Role Assumption (Eliminate Access Keys)

**Goal:** Replace static access keys with IMDS + per-container IAM roles. No application
code changes — only infrastructure and container startup configuration.

### 2.1 — IAM Roles (already created)

| Role                          | Trust Policy            | Permissions                          |
|-------------------------------|------------------------|--------------------------------------|
| `instance-base-role`          | ec2.amazonaws.com       | sts:AssumeRole on the 3 roles below  |
| `container-a-s3-role`         | instance-base-role ARN  | s3:GetObject, s3:PutObject on bucket |
| `container-b-dynamodb-role`   | instance-base-role ARN  | dynamodb:GetItem, PutItem, Query     |
| `container-c-kms-role`        | instance-base-role ARN  | kms:Encrypt, kms:Decrypt on key      |

EC2 instance metadata is already configured:
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"    # IMDSv2 only
  http_put_response_hop_limit = 2             # Allow containers to reach IMDS
}
```

### 2.2 — AWS Config Profiles (already on instance)

Located at `/home/appuser/aws-configs/` on the instance:

```ini
# container-a-config
[profile container-role]
role_arn = arn:aws:iam::ACCOUNT:role/container-roles-demo-container-a-s3
credential_source = Ec2InstanceMetadata
region = us-east-1
```

### 2.3 — Phase 2 Container Launch (deploy-roles.sh)

```bash
podman run -d \
  --network pasta \
  -v "$HOME/aws-configs/container-a-config:/home/app/.aws/config:ro,z" \
  -e AWS_PROFILE=container-role \
  -e AWS_DEFAULT_REGION=us-east-1 \
  --name container-a \
  container-a:latest
```

Key differences from Phase 1:
- `--network pasta` — pasta networking for IMDS reachability
- Config file mounted read-only with `:z` for SELinux
- `AWS_PROFILE` tells the SDK which profile to use
- **No access keys anywhere**
- **No application code changes**

### 2.4 — Validation (Phase 2)

- [ ] `podman ps` shows 3 running containers under `appuser`
- [ ] Container A logs show successful S3 operations (same as Phase 1)
- [ ] Container B logs show successful DynamoDB operations
- [ ] Container C logs show successful KMS operations
- [ ] **No static access keys in container env vars** (`make keys` shows only `AWS_PROFILE`)
- [ ] CloudTrail shows `userIdentity.type = AssumedRole` (not IAMUser)
- [ ] Each container can ONLY access its designated service
- [ ] Credentials auto-refresh after 1+ hour of runtime
- [ ] IMDS access works from within containers

### 2.5 — Optional Cleanup (after demo)

After the demo is complete and you no longer need Phase 1:
1. Delete IAM users and access keys from `iam_legacy.tf`
2. Remove access key outputs from `outputs.tf`
3. Remove legacy key variables from `ec2.tf` templatefile block
4. Remove `deploy-legacy.sh` from `user_data.sh.tftpl`
5. `terraform apply` to clean up

---

## Lessons Learned / Gotchas

These issues were encountered during initial build and are already resolved in the code:

| Issue | Root Cause | Fix Applied |
|-------|-----------|-------------|
| Free Tier rejection | t2.micro no longer Free Tier eligible | Use t3.micro |
| RHEL AMI not Free Tier | RHEL has hourly license cost | Use Fedora 41 (free, includes Podman) |
| Amazon Linux 2023 no Podman | Podman not in AL2023 default repos | Use Fedora 41 instead |
| Fedora AMI requires subscription | AWS Marketplace one-time free subscription | Subscribe via console |
| user_data exceeds 16KB | Embedding all scripts + app code is too large | Use `base64gzip()` instead of `base64encode()` |
| SELinux blocks config mounts | Fedora Enforcing mode denies container reads | Add `:z` flag to volume mounts (`:ro,z`) |
| Terraform template errors | `${var:-}` and `%{http_code}` parsed as directives | Escape as `%%{http_code}`, use `.env` file instead of bash defaults |
| IAM tag validation | Parentheses `(S3)` not allowed in tag values | Changed to `- S3` |
| AWS CLI region mismatch | CLI was us-east-2, Terraform was us-east-1 | `aws configure set region us-east-1` |

---

## File Structure (Current)

```
contianer-with-roles-demo/
├── PLAN.md                          # This file
├── Makefile                         # make phase1/phase2/status/logs/keys/ssh
├── infra/
│   ├── main.tf                      # Provider, data sources
│   ├── variables.tf                 # Input variables
│   ├── terraform.tfvars             # us-east-1, t3.micro, container-roles-demo
│   ├── vpc.tf                       # VPC, subnet, IGW
│   ├── security_group.tf            # SSH + egress
│   ├── ec2.tf                       # Fedora 41 EC2, instance profile, IMDSv2
│   ├── user_data.sh.tftpl           # Bootstrap template (gzipped)
│   ├── iam_legacy.tf                # Phase 1: 3 IAM users + access keys
│   ├── iam_policies.tf              # Scoped policies (used by both phases)
│   ├── iam_roles.tf                 # Phase 2: 3 container roles
│   ├── iam_instance_profile.tf      # Instance base role + profile
│   ├── kms.tf                       # KMS key (policy allows both legacy + role)
│   ├── dynamodb.tf                  # DynamoDB table
│   ├── s3.tf                        # S3 bucket
│   └── outputs.tf                   # All outputs
├── containers/                      # Local reference copies
│   ├── container-a/ (Dockerfile, app.py)
│   ├── container-b/ (Dockerfile, app.py)
│   └── container-c/ (Dockerfile, app.py)
├── aws-configs/                     # Template AWS configs (actual populated on instance)
│   ├── container-a-config
│   ├── container-b-config
│   └── container-c-config
└── scripts/                         # Local reference copies
    ├── deploy-legacy.sh
    └── deploy-roles.sh
```

---

## Quick Start (Resuming Later)

### Prerequisites
- AWS CLI configured for `us-east-1`
- Key pair `container-roles-demo` exists in us-east-1 (PEM at `~/.ssh/container-roles-demo.pem`)
- Fedora 41 AMI subscription active in AWS Marketplace

### Deploy from scratch
```bash
cd infra
terraform init
terraform apply
# Wait ~3 minutes for user_data bootstrap to complete
cd ..
make status    # verify 3 containers running
make logs      # verify operations succeeding
```

### Tear down
```bash
cd infra
terraform destroy
```

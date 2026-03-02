# Container-Level IAM Role Assumption via IMDS

This document explains how rootless Podman containers running on an EC2 instance assume individual, scoped IAM roles — without static access keys, custom credential vending services, or application code changes.

---

## Problem Statement

A common pattern in containerized workloads on EC2 is to inject static AWS access keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) as environment variables into each container. This approach has significant drawbacks:

- **Key rotation burden** — Static keys must be rotated manually or through automation. Missed rotations create long-lived credentials.
- **Secret sprawl** — Keys appear in environment variables, container definitions, deployment scripts, and potentially in logs.
- **Blast radius** — A compromised key grants access until it is discovered and revoked. There is no automatic expiration.
- **Auditability** — CloudTrail logs attribute actions to the IAM user, not to a specific container or workload, making it harder to trace activity.

This project eliminates all static keys by having each container assume its own scoped IAM role through the EC2 Instance Metadata Service (IMDS).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  EC2 Instance (Fedora 41, Podman 5.x, IMDSv2 hop_limit=2)         │
│  Instance Profile: instance-base-role                               │
│    └─ Only permission: sts:AssumeRole for role-a, role-b, role-c   │
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

---

## The Chain of Trust

Role assumption follows a two-hop chain. Each link in the chain is enforced by an IAM trust policy.

```
Container process (boto3)
  │
  ├─ 1. Reads ~/.aws/config → finds credential_source = Ec2InstanceMetadata
  │
  ├─ 2. Calls IMDS (169.254.169.254) → receives instance-base-role temp creds
  │
  ├─ 3. Reads ~/.aws/config → finds role_arn = container-specific-role
  │
  ├─ 4. Calls sts:AssumeRole using instance-base-role creds → receives
  │     container-role temp creds (scoped to one service)
  │
  └─ 5. Uses container-role temp creds for AWS API calls (S3, DynamoDB, or KMS)
```

The application code never participates in this process. It simply calls `boto3.client('s3')` or equivalent, and the SDK handles the entire credential chain internally.

---

## IAM Role Structure

Four IAM roles work together to implement this pattern:

### 1. Instance Base Role (`instance-base-role`)

Defined in `infra/iam_instance_profile.tf`.

**Trust policy:** Allows the EC2 service to assume this role.

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "ec2.amazonaws.com"
  },
  "Action": "sts:AssumeRole"
}
```

**Permissions:** Can only assume the three container roles. It has no direct access to S3, DynamoDB, KMS, or any other AWS service.

```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRole",
  "Resource": [
    "arn:aws:iam::ACCOUNT:role/container-a-s3-role",
    "arn:aws:iam::ACCOUNT:role/container-b-dynamodb-role",
    "arn:aws:iam::ACCOUNT:role/container-c-kms-role"
  ]
}
```

This role is attached to the EC2 instance via an instance profile.

### 2. Container A Role (`container-a-s3-role`)

Defined in `infra/iam_roles.tf`.

**Trust policy:** Only the instance base role can assume it.

```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT:role/instance-base-role"
  },
  "Action": "sts:AssumeRole"
}
```

**Permissions:** Scoped to S3 operations on one bucket only.

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::demo-bucket/*"
},
{
  "Effect": "Allow",
  "Action": ["s3:ListBucket"],
  "Resource": "arn:aws:s3:::demo-bucket"
}
```

### 3. Container B Role (`container-b-dynamodb-role`)

**Trust policy:** Same pattern — only the instance base role can assume it.

**Permissions:** Scoped to DynamoDB operations on one table.

```json
{
  "Effect": "Allow",
  "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"],
  "Resource": "arn:aws:dynamodb:us-east-1:ACCOUNT:table/demo-table"
}
```

### 4. Container C Role (`container-c-kms-role`)

**Trust policy:** Same pattern — only the instance base role can assume it.

**Permissions:** Scoped to KMS operations on one key.

```json
{
  "Effect": "Allow",
  "Action": ["kms:Encrypt", "kms:Decrypt"],
  "Resource": "arn:aws:kms:us-east-1:ACCOUNT:key/KEY-ID"
}
```

### Least Privilege Enforcement

Each container can only access its designated service. Container A cannot read from DynamoDB. Container B cannot call KMS. Container C cannot write to S3. The instance base role itself has no service-level permissions — it is purely a trust anchor.

---

## IMDS Configuration

The EC2 Instance Metadata Service is how containers obtain the initial temporary credentials for the instance base role.

### IMDSv2 (Token-Required Mode)

The instance is configured to require IMDSv2, which uses a session-oriented token model:

```hcl
# infra/ec2.tf
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"    # IMDSv2 only
  http_put_response_hop_limit = 2             # Critical for containers
}
```

IMDSv2 requires a `PUT` request to obtain a session token before any metadata can be read. This defends against SSRF attacks where an attacker tricks the application into making a `GET` request to `169.254.169.254` — with IMDSv2, a simple `GET` is rejected.

### Why `hop_limit = 2`

The `http_put_response_hop_limit` controls the IP TTL (time-to-live) for the IMDS token response. Each network hop decrements the TTL by one.

- **`hop_limit = 1` (default):** The token response reaches the EC2 host OS, but the network hop from container to host (through the `pasta` network stack) decrements the TTL to zero. The container never receives the token. IMDS is unreachable from containers.
- **`hop_limit = 2`:** The token response survives the extra hop through the container networking layer and reaches the container process. IMDS is reachable.

This is the minimum setting required for any containerized workload to use IMDS for credential retrieval.

### Pasta Networking

Podman's `pasta` network mode provides user-mode networking for rootless containers. Unlike `slirp4netns` (the older default), `pasta` maps the container's network namespace to the host using a lightweight translation layer. It preserves connectivity to link-local addresses like `169.254.169.254`, which is essential for IMDS access.

Containers are launched with `--network pasta`:

```bash
podman run -d \
  --network pasta \
  ...
```

---

## AWS Config Profiles: Per-Container Role Selection

Each container receives a unique AWS CLI/SDK configuration file mounted at `~/.aws/config` inside the container. This is the mechanism that directs each container to assume a different role.

### Config File Format

```ini
[profile container-role]
role_arn = arn:aws:iam::ACCOUNT:role/container-a-s3-role
credential_source = Ec2InstanceMetadata
region = us-east-1
```

Key directives:

- **`role_arn`** — The specific IAM role this container should assume. Each container's config file contains a different role ARN.
- **`credential_source = Ec2InstanceMetadata`** — Tells the SDK to obtain the base credentials from IMDS rather than from a credentials file or environment variables. The SDK calls IMDS to get the instance profile's temporary credentials, then uses those to call `sts:AssumeRole` for the target `role_arn`.
- **`region`** — The AWS region for API calls.

### How the Config is Delivered

The `deploy-roles.sh` script generates each config file on the host and bind-mounts it read-only into the container:

```bash
# deploy-roles.sh (lines 82-89)
podman run -d \
  --network pasta \
  -v "$AWS_CONFIGS_DIR/container-a-config:/home/app/.aws/config:ro,z" \
  -e AWS_PROFILE=container-role \
  -e AWS_DEFAULT_REGION="$REGION" \
  -e S3_BUCKET="$S3_BUCKET" \
  --name container-a \
  container-a:latest
```

- **`:ro`** — Read-only mount. The container cannot modify the config.
- **`:z`** — SELinux shared label. Required on Fedora (which runs SELinux in enforcing mode) so the container process can read the mounted file.
- **`AWS_PROFILE=container-role`** — Environment variable that tells the SDK which profile to load from the config file.

### Why This Requires Zero Code Changes

The boto3 SDK's default credential resolution chain checks (in order):

1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. AWS config/credentials files (respecting `AWS_PROFILE`)
3. Container credential provider (ECS)
4. Instance metadata (IMDS)

In Phase 1 (static keys), the credentials are found at step 1 (environment variables). In Phase 2 (roles), the `AWS_PROFILE` environment variable directs the SDK to step 2 (config file), which in turn chains to step 4 (IMDS) via `credential_source`, then performs `sts:AssumeRole`. The application code — which just calls `boto3.client('s3')` — never changes.

---

## Credential Lifecycle

### Automatic Refresh

The boto3 SDK manages credential refresh transparently:

1. IMDS credentials for the instance base role are cached by the SDK and refreshed automatically. IMDS itself rotates these credentials roughly every 6 hours, providing new credentials at least 5 minutes before the old ones expire.
2. Assumed role credentials (from `sts:AssumeRole`) default to a 1-hour session. The SDK tracks the expiration time and calls `sts:AssumeRole` again before they expire.
3. The application never sees credential expiration or renewal. It simply makes AWS API calls.

### No Credential Storage

No credentials are written to disk anywhere:

- IMDS credentials exist only in memory (retrieved over HTTP from `169.254.169.254`)
- Assumed role credentials exist only in the SDK's in-memory cache
- The only file on disk is the AWS config file, which contains the role ARN (not a secret) and the instruction to use IMDS

---

## Security Properties

| Property | Static Keys (Phase 1) | IMDS + Roles (Phase 2) |
|---|---|---|
| Credential lifetime | Indefinite until rotated | 1 hour (auto-refreshed) |
| Credentials on disk | Access keys in env vars | None — role ARN only |
| Rotation mechanism | Manual | Automatic (SDK + IMDS) |
| Per-container scoping | Yes (different keys) | Yes (different roles) |
| CloudTrail attribution | `userIdentity.type: IAMUser` | `userIdentity.type: AssumedRole` |
| Revocation | Delete/deactivate key | Modify trust policy or instance profile |
| Blast radius of compromise | Key valid from anywhere until revoked | Creds valid for ≤1 hour, only from this instance |

### CloudTrail Forensics

With role assumption, CloudTrail entries include:

```json
{
  "userIdentity": {
    "type": "AssumedRole",
    "arn": "arn:aws:sts::ACCOUNT:assumed-role/container-a-s3-role/SESSION",
    "sessionContext": {
      "sessionIssuer": {
        "arn": "arn:aws:iam::ACCOUNT:role/instance-base-role"
      }
    }
  }
}
```

This tells you exactly which container role made the call and that it originated from the EC2 instance's base role — far more useful for incident response than a generic IAM user identity.

---

## Terraform Resource Map

| File | Resources | Purpose |
|---|---|---|
| `iam_instance_profile.tf` | `instance-base-role`, instance profile | EC2 trust anchor with `sts:AssumeRole` only |
| `iam_roles.tf` | 3 container roles + inline policies | Per-container scoped permissions |
| `iam_policies.tf` | 3 legacy user policies | Phase 1 only (static key permissions) |
| `iam_legacy.tf` | 3 IAM users + access keys | Phase 1 only (to be deleted after migration) |
| `ec2.tf` | EC2 instance | Instance profile attachment, IMDSv2 config |
| `kms.tf` | KMS key | Key policy allows both legacy user and container role |
| `s3.tf` | S3 bucket | Bucket used by Container A |
| `dynamodb.tf` | DynamoDB table | Table used by Container B |

---

## FAQ

**Q: Why not use ECS task roles instead?**
A: This workload runs on a standalone EC2 instance with Podman, not on ECS. ECS task roles rely on the ECS agent to vend credentials via a container-local metadata endpoint. That infrastructure does not exist here. The IMDS + config profile approach achieves the same per-container isolation without requiring ECS.

**Q: Could one container assume another container's role?**
A: In theory, yes — any process on the instance that can reach IMDS could assume any of the three container roles, because the trust policy is on the instance base role (not on a specific container). True container-level isolation of credentials would require a credential vending service or ECS-style task roles. However, this approach eliminates the far larger risk of static keys while maintaining per-container scoping through configuration.

**Q: What happens if IMDS goes down?**
A: The SDK would fail to refresh credentials once the current cached credentials expire (within 1 hour for assumed role creds). AWS API calls would start failing with `ExpiredTokenException`. IMDS outages are extremely rare as it is a core EC2 infrastructure service.

**Q: Why IMDSv2 instead of IMDSv1?**
A: IMDSv2 requires a `PUT` request to obtain a session token before metadata can be read. This prevents SSRF-based credential theft where an attacker tricks the application into making a `GET` request to the metadata endpoint. With IMDSv2, a simple `GET` returns nothing.

**Q: Can this work with Docker instead of Podman?**
A: Yes. The same approach works with Docker containers on EC2. The key requirements are: (1) `hop_limit >= 2` on the instance metadata options, (2) a network mode that allows containers to reach `169.254.169.254`, and (3) mounting the AWS config file into each container. Docker's default bridge networking supports IMDS access with `hop_limit=2`.

# GWen Infrastructure

Terraform modules and independently deployed root stacks for shared GWen
platform resources. This repository does not own application AgentCore Runtime
instances. Each executable repository owns its Runtime, ECR repository,
execution role, environment, and Gateway target.

## Ownership

| Root stack | Owns |
| --- | --- |
| `bootstrap` | Encrypted, versioned Terraform state bucket and lockfile support |
| `identity` | AWS KMS signing identities and the SSM contract for externally managed Entra applications |
| `gateway` | One tenant-scoped AgentCore Gateway, policy engine, and service role |
| `registry` | A tenant-scoped Agent Registry container and its published identifier |
| `artifacts` | Artifact S3 bucket, DynamoDB authorization index, KMS key, lifecycle, and consumer IAM policies |
| `memory` | Shared AgentCore Memory resource, strategies, encryption, and execution role |
| `observability` | Shared log retention and platform telemetry destinations |
| `catalog` | Versioned Bedrock prompts and approved Agent Registry specialist records |

Each root has its own backend and state. Never combine these roots into one
state, and never let an application state manage the same resource.

Application repositories consume `modules/agentcore-runtime` locally during
the initial modularization. After this repository has a remote, replace the
relative module source with a pinned Git tag or private Terraform Registry
version.

## Application Ownership

```text
gwen-chat                         Primary AgentCore Runtime
gwen-deep-research-agent          Deep Research AgentCore Runtime
m365-mcp-server                   M365 MCP Runtime and Gateway target
document-intelligence-mcp-server  Document MCP Runtime and Gateway target
web-grounding-mcp-server          Web Grounding MCP Runtime and Gateway target
gwen-strands                      Python package only; no Runtime
```

## State Layout

Recommended keys are intentionally independent:

```text
gwen/dev/bootstrap.tfstate
gwen/dev/identity/<tenant>.tfstate
gwen/dev/gateway/<tenant>.tfstate
gwen/dev/registry/<tenant>.tfstate
gwen/dev/artifacts.tfstate
gwen/dev/memory.tfstate
gwen/dev/observability.tfstate
gwen/dev/catalog/<tenant>.tfstate
gwen/dev/runtimes/<application>/<tenant>.tfstate
```

Copy each `backend.tf.example` to `backend.tf` after the bootstrap stack is
applied. Use the S3 backend's native `use_lockfile = true`; a DynamoDB lock table
is not required by current Terraform.

## Environment Contracts

Stacks publish small, non-secret contracts under `/gwen/<environment>/...` in
AWS Systems Manager Parameter Store. Secrets and private keys do not belong in
Parameter Store or Terraform outputs. Application stacks consume these
parameters instead of reading another stack's complete Terraform state.

The deprecated `gwen-chat/infrastructure/agentcore` AWS root was destroyed and
removed. New AWS resources may be deployed from these modular stacks without
importing its state. The existing development Entra resources were moved to the
standalone `gwen-entra` repository without replacing registrations or
changing client IDs. This repository has no AzureAD provider and requires no
Entra administrator credential. Read [MIGRATION.md](MIGRATION.md) for the state
split and [DEPLOYMENT.md](DEPLOYMENT.md) for a local manual rollout. No CI/CD
system is required by this layout.

MongoDB provisioning belongs to the separate `gwen-mongo` repository or the
enterprise database team's Terraform. Document Intelligence consumes only the
published Secrets Manager and SSM contract; this repository does not require
MongoDB Atlas credentials or own database state. The separate `gwen-network`
repository owns the VPC, subnets, NAT Gateway, Elastic IP, routes, and endpoints.

## External Entra Contract

`stacks/identity` accepts four deployed values from whichever Terraform owns
Microsoft Entra in the target environment:

```text
entra_tenant_id
gwchat_bff_client_id
agent_api_client_id
m365_mcp_client_id
```

The development environment obtains them from `gwen-entra`; an
enterprise environment obtains them from its Entra team. The stack derives the
OIDC discovery URL, creates the two AWS KMS signing keys, and publishes the
complete AgentCore identity contract to SSM. Client IDs and tenant IDs are
configuration identifiers, not credentials.

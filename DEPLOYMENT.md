# Manual Terraform Deployment

This repository intentionally does not require a CI/CD platform. Each stack is
an independent Terraform root and may be planned and applied manually. Use one
backend key per root and tenant as documented in the main README.

## Dependency Order

```text
bootstrap
  -> external Entra applications
  -> identity/<tenant> AWS contract
  -> artifacts, memory, observability
  -> external MongoDB contract and document egress
  -> gateway/<tenant>
  -> registry/<tenant>
  -> application Runtime roots
  -> catalog/<tenant>
```

The catalog is last because its approved Registry records reference Gateway
targets published by the MCP application roots.

## Shared Stacks

For each stack, copy `backend.tf.example` to an untracked `backend.tf`, copy
`terraform.tfvars.example` to an untracked tenant/environment tfvars file, and
then run:

```bash
terraform init
terraform plan -var-file=dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
```

Apply `identity`, `gateway`, `registry`, and `catalog` once per accepted Entra
tenant. Apply `artifacts`, `memory`, and `observability` once per environment.
MongoDB belongs to `gwen-mongo` or the enterprise database team's Terraform.
Before deploying Document Intelligence, that owner must publish
`/gwen/<environment>/platform/document-database/mongodb-secret-arn` and
`/gwen/<environment>/platform/document-database/database-name`. Apply the
separate `gwen-network/stacks/document-egress` when controlled public egress is
required; network topology and database state do not live in this repository.

Identity has a deliberate two-pass certificate handoff. First obtain the four
deployed Entra IDs from `gwen-entra` or the target environment's
Entra team and apply `stacks/identity`. The stack creates two AWS KMS signing
keys and publishes the identifiers to SSM. Run
`stacks/identity/scripts/export_kms_certificates.py` and give only the two
public `.crt` files to the Entra owner. After they upload those exact
certificates and confirm the thumbprints, set
`agent_api_certificate_thumbprint` and `m365_mcp_certificate_thumbprint` and
apply the AWS identity stack again.

The exporter requires Python 3, Terraform, and AWS CLI. It has no OpenSSL or
third-party Python dependency and behaves consistently on Linux and macOS. The
legacy `export-kms-certificates.sh` entry point remains as a compatibility
wrapper around the Python exporter.

The AWS identity root accepts the four values either through a tenant tfvars
file or standard Terraform environment variables:

```bash
export TF_VAR_entra_tenant_id=<directory-tenant-id>
export TF_VAR_gwchat_bff_client_id=<bff-application-client-id>
export TF_VAR_agent_api_client_id=<agent-api-application-client-id>
export TF_VAR_m365_mcp_client_id=<m365-mcp-application-client-id>
```

It does not authenticate to Entra and must not receive Entra client secrets,
private certificates, Graph tokens, or Azure administrator credentials.

## Application Runtimes

Each executable repository contains `infrastructure/runtime`. For a new image:

1. Apply with `deploy_runtime=false` to create ECR and the execution role.
2. Run the root's `scripts/build-and-push.sh <immutable-image-tag>`.
3. Set the same `image_tag`, enable `deploy_runtime`, and apply again.

The application roots consume only the small SSM contracts published under
`/gwen/<environment>/...`. They do not read or share another root's Terraform
state. The M365 root also creates its two AgentCore Identity OAuth providers
and OAuth Gateway target. The Document and Web roots create IAM-authenticated
Gateway targets.

For the Document Runtime, use the MongoDB secret ARN published by the database
owner. Set `mongodb_secret_ssm_parameter_name` to
`/gwen/<environment>/platform/document-database/mongodb-secret-arn`. For a
standalone deployment without that stack, the first Runtime apply creates an
empty application-owned Secrets Manager container. Run
`document-intelligence-mcp-server/infrastructure/runtime/scripts/put-mongodb-secret.sh`
before enabling the Runtime. The helper prompts without echo and keeps the URI
out of tfvars, command history, SSM parameters, and Terraform outputs.

## Existing Development Resources

The deprecated AWS AgentCore dev resources and their Terraform root have been
destroyed, so the AWS stacks above start from clean state. Existing Entra
resources and state now belong to the standalone `gwen-entra`
repository. AWS KMS keys and the SSM identity contract remain under
`stacks/identity`. The split changes Terraform ownership only; it does not
destroy or recreate live resources. Review [MIGRATION.md](MIGRATION.md) before
applying either root.

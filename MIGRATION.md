# State Migration

The deprecated AWS AgentCore dev root was destroyed on September 1, 2026. New
shared AWS resources are managed by the independent roots in this repository;
application Runtime resources remain in their application repositories.

## Entra And AWS Identity Split

The former `stacks/identity` state combined two ownership domains:

```text
module.entra.*   Microsoft Entra applications and permissions
aws_kms_*        AWS private-key JWT signing keys
aws_ssm_*        AWS identity contract
```

The Entra configuration and its `module.entra.*` state addresses were moved to
the standalone `gwen-entra` repository. The AWS KMS, aliases, and SSM
addresses remain in `gwen-infrastructure/stacks/identity`. State references
were removed from the opposite state with `terraform state rm`; no remote
resource was destroyed.

The development client IDs remain:

```text
GWChat BFF:          0385c70e-3faf-4034-9fce-5d14f78bc82a
GuideWell Agent API: 58f9b7e1-0e71-4cca-8681-81e2508dd1fd
M365 MCP API:        2da11160-9752-4528-bae3-3f5fadd43ecc
```

Before applying either root after the split:

1. Back up both state files.
2. Confirm the Entra plan does not replace registrations or change client IDs.
3. Confirm the AWS identity plan does not replace either KMS key.
4. Confirm both roots agree on the four-value Entra contract and certificate
   thumbprints.

Never import the same Entra resource into both repositories, and never add the
AzureAD provider back to the AWS identity root.

## Ownership Map

```text
Entra registrations, scopes, consent, and public certificates -> gwen-entra or enterprise Entra Terraform
AWS signing KMS keys and identity SSM contract                  -> stacks/identity/<tenant>
AgentCore Gateway and policy engine                             -> stacks/gateway/<tenant>
Agent Registry                                                  -> stacks/registry/<tenant>
Bedrock prompts and Registry records                            -> stacks/catalog/<tenant>
Artifact S3, authorization index, and encryption                -> stacks/artifacts
AgentCore Memory                                                -> stacks/memory
MongoDB data plane and connection contract                      -> gwen-mongo or enterprise database Terraform
Network topology and controlled document egress                 -> gwen-network
Primary Runtime                                                 -> gwen-chat
Deep Research Runtime                                           -> gwen-deep-research-agent
M365 MCP Runtime and target                                     -> m365-mcp-server
Document MCP Runtime and target                                 -> document-intelligence-mcp-server
Web Grounding MCP Runtime and target                            -> web-grounding-mcp-server
```

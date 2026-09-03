# Development Environment

The root stacks remain under `stacks/`; this directory records the approved
development topology without creating a wrapper state that would couple them.

Current tenant roots should use separate backend keys for identity, Gateway,
Registry, catalog, and each JWT-authorized Runtime. Copy each stack's
`terraform.tfvars.example` into an ignored tenant-specific variable file when
applying locally.

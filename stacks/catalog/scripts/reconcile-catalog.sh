#!/usr/bin/env bash
set -euo pipefail

required=(AWS_REGION ENVIRONMENT TENANT_SLUG REGISTRY_ID GATEWAY_ID GATEWAY_URL M365_TARGET_ID BEDROCK_PROMPT_MODEL_ID)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required environment variable: %s\n' "${name}" >&2
    exit 2
  fi
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${GWEN_CATALOG_VENV_DIR:-${TMPDIR:-/tmp}/gwen-catalog-reconciler-venv}"
prompt_file="$(mktemp)"
trap 'rm -f "$prompt_file"' EXIT

if [[ ! -x "${VENV_DIR}/bin/python" ]] || ! "${VENV_DIR}/bin/python" -c 'import boto3' >/dev/null 2>&1; then
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/python" -m pip install \
    --disable-pip-version-check \
    --quiet \
    --requirement "${ROOT_DIR}/scripts/requirements.txt"
fi

"${VENV_DIR}/bin/python" "${ROOT_DIR}/scripts/reconcile-bedrock-prompts.py" \
  --region "${AWS_REGION}" \
  --environment "${ENVIRONMENT}" \
  --tenant-slug "${TENANT_SLUG}" \
  --model-id "${BEDROCK_PROMPT_MODEL_ID}" > "${prompt_file}"

"${VENV_DIR}/bin/python" "${ROOT_DIR}/scripts/reconcile-agent-registry.py" \
  --region "${AWS_REGION}" \
  --environment "${ENVIRONMENT}" \
  --registry-id "${REGISTRY_ID}" \
  --gateway-id "${GATEWAY_ID}" \
  --m365-gateway-url "${GATEWAY_URL}" \
  --m365-target-id "${M365_TARGET_ID}" \
  --document-gateway-url "${DOCUMENT_GATEWAY_URL:-}" \
  --document-target-id "${DOCUMENT_TARGET_ID:-}" \
  --web-gateway-url "${WEB_GATEWAY_URL:-}" \
  --web-target-id "${WEB_TARGET_ID:-}" \
  --m365-prompt-ref "$(jq -r '.prompt_refs.m365_evidence_agent' "${prompt_file}")" \
  --document-prompt-ref "$(jq -r '.prompt_refs.document_intelligence_agent' "${prompt_file}")" \
  --web-prompt-ref "$(jq -r '.prompt_refs.web_research_agent' "${prompt_file}")"

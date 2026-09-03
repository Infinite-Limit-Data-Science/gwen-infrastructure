#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="${TERRAFORM_BIN:-terraform}"
AWS_PROFILE="${AWS_PROFILE:-atlantic_genetics}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CERT_DIR="${CERT_DIR:-${ROOT_DIR}/.certs}"

mkdir -p "${CERT_DIR}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

agent_key_arn="$(${TF} -chdir="${ROOT_DIR}" output -raw agent_api_signing_key_arn)"
m365_key_arn="$(${TF} -chdir="${ROOT_DIR}" output -raw m365_signing_key_arn)"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${tmp_dir}/ca.key" >/dev/null 2>&1
openssl req -x509 -new -key "${tmp_dir}/ca.key" -sha256 -days 7 \
  -subj "/CN=GWen temporary KMS certificate issuer" -out "${tmp_dir}/ca.crt"

make_certificate() {
  local key_arn="$1"
  local common_name="$2"
  local output_name="$3"

  aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" kms get-public-key \
    --key-id "${key_arn}" --query PublicKey --output text \
    | base64 --decode > "${tmp_dir}/${output_name}.der"
  openssl pkey -pubin -inform DER -in "${tmp_dir}/${output_name}.der" \
    -out "${tmp_dir}/${output_name}.pem"
  openssl x509 -new -force_pubkey "${tmp_dir}/${output_name}.pem" \
    -subj "/CN=${common_name}" \
    -CA "${tmp_dir}/ca.crt" -CAkey "${tmp_dir}/ca.key" -CAcreateserial \
    -days 825 -sha256 -out "${CERT_DIR}/${output_name}.crt"
  openssl x509 -in "${CERT_DIR}/${output_name}.crt" -outform DER \
    | openssl dgst -sha256 -binary \
    | base64 | tr '+/' '-_' | tr -d '=\n' > "${CERT_DIR}/${output_name}.x5t-s256"
}

make_certificate "${agent_key_arn}" "GuideWell Agent API AgentCore OBO" "guidewell-agent-api-kms"
make_certificate "${m365_key_arn}" "GuideWell M365 MCP AgentCore OBO" "m365-mcp-kms"

printf 'Generated KMS-backed public certificates in %s\n' "${CERT_DIR}"

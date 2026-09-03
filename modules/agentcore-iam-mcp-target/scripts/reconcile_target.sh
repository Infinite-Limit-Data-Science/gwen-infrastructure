#!/usr/bin/env bash
set -euo pipefail

required=(AWS_REGION GATEWAY_ID RUNTIME_ENDPOINT TARGET_NAME TARGET_DESCRIPTION TARGET_PARAMETER_NAME)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required environment variable: %s\n' "${name}" >&2
    exit 2
  fi
done

aws_cli() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --no-cli-pager "$@"
  else
    aws --region "${AWS_REGION}" --no-cli-pager "$@"
  fi
}

target_id="$(aws_cli bedrock-agentcore-control list-gateway-targets \
  --gateway-identifier "${GATEWAY_ID}" \
  --query "items[?name=='${TARGET_NAME}'].targetId | [0]" --output text)"
target_file="$(mktemp)"
trap 'rm -f "$target_file" "$target_file.update"' EXIT

jq -n \
  --arg gateway "${GATEWAY_ID}" \
  --arg name "${TARGET_NAME}" \
  --arg description "${TARGET_DESCRIPTION}" \
  --arg endpoint "${RUNTIME_ENDPOINT}" \
  --arg region "${AWS_REGION}" \
  --argjson headers "${ALLOWED_REQUEST_HEADERS:-[]}" \
  '{
    gatewayIdentifier: $gateway,
    name: $name,
    description: $description,
    targetConfiguration: {
      mcp: {
        mcpServer: {
          endpoint: $endpoint,
          listingMode: "DYNAMIC"
        }
      }
    },
    credentialProviderConfigurations: [{
      credentialProviderType: "GATEWAY_IAM_ROLE",
      credentialProvider: {
        iamCredentialProvider: {
          service: "bedrock-agentcore",
          region: $region
        }
      }
    }],
    metadataConfiguration: {
      allowedRequestHeaders: $headers
    }
  }' > "${target_file}"

if [[ -z "${target_id}" || "${target_id}" == "None" ]]; then
  aws_cli bedrock-agentcore-control create-gateway-target \
    --cli-input-json "file://${target_file}" >/dev/null
  target_id="$(aws_cli bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" \
    --query "items[?name=='${TARGET_NAME}'].targetId | [0]" --output text)"
else
  jq --arg target "${target_id}" '. + {targetId: $target}' "${target_file}" \
    > "${target_file}.update"
  aws_cli bedrock-agentcore-control update-gateway-target \
    --cli-input-json "file://${target_file}.update" >/dev/null
fi

if [[ -z "${target_id}" || "${target_id}" == "None" ]]; then
  printf 'Gateway target was reconciled but no target ID was returned.\n' >&2
  exit 1
fi

aws_cli ssm put-parameter \
  --name "${TARGET_PARAMETER_NAME}" \
  --type String \
  --value "${target_id}" \
  --overwrite >/dev/null

printf 'Reconciled Gateway target %s (%s).\n' "${TARGET_NAME}" "${target_id}"

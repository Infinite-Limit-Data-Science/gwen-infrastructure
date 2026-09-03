#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import boto3


PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"
TEMPLATE_VARIABLE = re.compile(r"{{\s*([A-Za-z][A-Za-z0-9_]*)\s*}}")
DEFAULT_VARIANT = "default"


@dataclass(frozen=True)
class PromptSpec:
    key: str
    name: str
    description: str
    template_path: Path


def _prompt_specs(environment: str, tenant_slug: str) -> tuple[PromptSpec, ...]:
    return (
        PromptSpec(
            key="m365_evidence_agent",
            name=f"gwen-m365-evidence-{tenant_slug}-{environment}",
            description="Governed specialist instructions for Microsoft 365 evidence.",
            template_path=PROMPT_DIR / "m365-evidence-agent.txt",
        ),
        PromptSpec(
            key="document_intelligence_agent",
            name=f"gwen-document-intelligence-{tenant_slug}-{environment}",
            description="Governed specialist instructions for document intelligence.",
            template_path=PROMPT_DIR / "document-intelligence-agent.txt",
        ),
        PromptSpec(
            key="web_research_agent",
            name=f"gwen-web-research-{tenant_slug}-{environment}",
            description="Governed specialist instructions for public-web evidence.",
            template_path=PROMPT_DIR / "web-research-agent.txt",
        ),
    )


def _pages(client: Any, operation: str, result_key: str, **kwargs: Any):
    token = None
    while True:
        request = dict(kwargs)
        if token:
            request["nextToken"] = token
        response = getattr(client, operation)(**request)
        yield from response.get(result_key) or []
        token = response.get("nextToken")
        if not token:
            return


def _template(spec: PromptSpec) -> tuple[str, tuple[str, ...]]:
    if not spec.template_path.is_file():
        raise FileNotFoundError(f"Managed prompt template not found: {spec.template_path}")
    text = spec.template_path.read_text(encoding="utf-8").strip()
    if not text:
        raise ValueError(f"Managed prompt template is empty: {spec.template_path}")
    variables = tuple(sorted(set(TEMPLATE_VARIABLE.findall(text))))
    return text, variables


def _variant(
    *, template: str, variables: tuple[str, ...], model_id: str
) -> dict[str, Any]:
    return {
        "name": DEFAULT_VARIANT,
        "modelId": model_id,
        "templateType": "TEXT",
        "templateConfiguration": {
            "text": {
                "text": template,
                "inputVariables": [{"name": name} for name in variables],
            }
        },
    }


def _matches(response: dict[str, Any], desired: dict[str, Any]) -> bool:
    if str(response.get("defaultVariant") or "") != DEFAULT_VARIANT:
        return False
    current = next(
        (
            item
            for item in response.get("variants") or []
            if item.get("name") == DEFAULT_VARIANT
        ),
        None,
    )
    if not isinstance(current, dict):
        return False
    current_text = ((current.get("templateConfiguration") or {}).get("text") or {})
    desired_text = ((desired.get("templateConfiguration") or {}).get("text") or {})
    return (
        current.get("modelId") == desired.get("modelId")
        and current.get("templateType") == "TEXT"
        and str(current_text.get("text") or "").strip()
        == str(desired_text.get("text") or "").strip()
        and {
            str(item.get("name") or "")
            for item in current_text.get("inputVariables") or []
        }
        == {
            str(item.get("name") or "")
            for item in desired_text.get("inputVariables") or []
        }
    )


def _versioned_arn(arn: str, version: str) -> str:
    base = str(arn or "").strip()
    number = str(version or "").strip()
    if not base or not number.isdigit() or int(number) < 1:
        raise ValueError("Bedrock did not return a numbered prompt version")
    return base if base.endswith(f":{number}") else f"{base}:{number}"


def _existing_prompt_id(client: Any, name: str) -> str | None:
    matches = {
        str(item.get("id") or "").strip()
        for item in _pages(client, "list_prompts", "promptSummaries", maxResults=100)
        if item.get("name") == name and str(item.get("id") or "").strip()
    }
    if len(matches) > 1:
        raise RuntimeError(f"Multiple Bedrock prompts have the managed name {name!r}")
    return next(iter(matches), None)


def _latest_numbered_prompt(client: Any, prompt_id: str) -> dict[str, Any] | None:
    versions = sorted(
        (
            item
            for item in _pages(
                client,
                "list_prompts",
                "promptSummaries",
                promptIdentifier=prompt_id,
                maxResults=100,
            )
            if str(item.get("version") or "").isdigit()
        ),
        key=lambda item: int(item["version"]),
        reverse=True,
    )
    if not versions:
        return None
    return client.get_prompt(
        promptIdentifier=prompt_id,
        promptVersion=str(versions[0]["version"]),
    )


def _ensure_prompt(
    client: Any,
    *,
    spec: PromptSpec,
    model_id: str,
    environment: str,
) -> str:
    template, variables = _template(spec)
    desired_variant = _variant(
        template=template,
        variables=variables,
        model_id=model_id,
    )
    prompt_id = _existing_prompt_id(client, spec.name)
    if prompt_id is None:
        created = client.create_prompt(
            name=spec.name,
            description=spec.description,
            defaultVariant=DEFAULT_VARIANT,
            variants=[desired_variant],
            tags={"Application": "GWen", "Environment": environment},
        )
        prompt_id = str(created.get("id") or "").strip()
        if not prompt_id:
            raise RuntimeError(f"Bedrock did not return an ID for prompt {spec.name}")
    else:
        draft = client.get_prompt(
            promptIdentifier=prompt_id,
            promptVersion="DRAFT",
        )
        if not _matches(draft, desired_variant):
            client.update_prompt(
                promptIdentifier=prompt_id,
                name=spec.name,
                description=spec.description,
                defaultVariant=DEFAULT_VARIANT,
                variants=[desired_variant],
            )

    latest = _latest_numbered_prompt(client, prompt_id)
    if latest is not None and _matches(latest, desired_variant):
        return _versioned_arn(latest["arn"], latest["version"])

    version = client.create_prompt_version(
        promptIdentifier=prompt_id,
        description=f"Managed GWen {environment} prompt version",
        tags={"Application": "GWen", "Environment": environment},
    )
    return _versioned_arn(version["arn"], version["version"])


def reconcile_prompts(
    client: Any,
    *,
    environment: str,
    tenant_slug: str,
    model_id: str,
) -> dict[str, str]:
    return {
        spec.key: _ensure_prompt(
            client,
            spec=spec,
            model_id=model_id,
            environment=environment,
        )
        for spec in _prompt_specs(environment, tenant_slug)
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--environment", default="dev")
    parser.add_argument("--tenant-slug", required=True)
    parser.add_argument("--model-id", required=True)
    args = parser.parse_args()

    model_id = str(args.model_id or "").strip()
    if not model_id:
        raise ValueError("--model-id must be non-empty")
    client = boto3.client("bedrock-agent", region_name=args.region)
    prompt_refs = reconcile_prompts(
        client,
        environment=args.environment,
        tenant_slug=args.tenant_slug,
        model_id=model_id,
    )
    print(json.dumps({"prompt_refs": prompt_refs}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Bedrock prompt reconciliation failed: {exc}", file=sys.stderr)
        raise

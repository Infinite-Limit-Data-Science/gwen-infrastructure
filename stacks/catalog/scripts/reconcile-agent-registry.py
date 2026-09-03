#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import time
from typing import Any

import boto3

OBSOLETE_RECORD_NAMES = frozenset({"gwen_primary_agent"})


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


def _wait_registry_ready(client: Any, registry_id: str) -> None:
    for _ in range(60):
        response = client.get_registry(registryId=registry_id)
        status = response.get("status")
        if status == "READY":
            return
        if status in {"CREATE_FAILED", "UPDATE_FAILED", "DELETE_FAILED"}:
            raise RuntimeError(
                f"Agent Registry {registry_id} entered {status}: "
                f"{response.get('statusReason') or 'unknown reason'}"
            )
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for Agent Registry {registry_id}")


def _wait_record_approved(client: Any, registry_id: str, record_id: str) -> None:
    submitted = False
    for _ in range(90):
        response = client.get_registry_record(
            registryId=registry_id,
            recordId=record_id,
        )
        status = response.get("status")
        if status == "APPROVED":
            return
        if status == "DRAFT" and not submitted:
            client.submit_registry_record_for_approval(
                registryId=registry_id,
                recordId=record_id,
            )
            submitted = True
        elif status in {"REJECTED", "DEPRECATED", "CREATE_FAILED", "UPDATE_FAILED"}:
            raise RuntimeError(
                f"Agent Registry record {record_id} entered {status}: "
                f"{response.get('statusReason') or 'unknown reason'}"
            )
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for Registry record {record_id}")


def _gateway_target(client: Any, *, gateway_id: str, target_id: str) -> dict[str, str]:
    response = client.get_gateway_target(
        gatewayIdentifier=gateway_id,
        targetId=target_id,
    )
    status = str(response.get("status") or "").strip().upper()
    if status != "READY":
        raise RuntimeError(
            f"Gateway target {target_id!r} is not READY (status={status or 'unknown'})"
        )
    name = str(response.get("name") or "").strip()
    if not name or "___" in name:
        raise RuntimeError(f"Gateway target {target_id!r} returned an invalid name")
    return {"id": target_id, "name": name}


def _profile(
    *,
    agent_type: str,
    tier: str,
    description: str,
    prompt_ref: str,
    capability_refs: list[str],
    gateway_url: str,
    gateway_target_id: str,
    gateway_target_name: str,
    server_id: str,
    trusted_arguments: dict[str, str] | None = None,
    max_turns: int = 8,
    timeout_seconds: int = 180,
) -> dict[str, Any]:
    if not prompt_ref.startswith("arn:") or ":prompt/" not in prompt_ref:
        raise ValueError("prompt_ref must be an immutable Bedrock prompt ARN")
    return {
        "agent_type": agent_type,
        "tier": tier,
        "description": description,
        "prompt_ref": prompt_ref,
        "model_policy": "specialist-default",
        "capability_refs": capability_refs,
        "loop_policy": {
            "max_react_turns": max_turns,
            "timeout_seconds": timeout_seconds,
        },
        "verification_profile": {
            "type": "configuration_and_execution_evidence",
        },
        "mcp_servers": [
            {
                "server_id": server_id,
                "gateway_url": gateway_url,
                "gateway_target_id": gateway_target_id,
                "gateway_target_name": gateway_target_name,
                "capability_refs": capability_refs,
                "trusted_arguments": trusted_arguments or {},
            }
        ],
    }


def _desired_records(
    args: argparse.Namespace,
    prompt_refs: dict[str, str],
    targets: dict[str, dict[str, str]],
) -> list[dict[str, Any]]:
    records = [
        _profile(
            agent_type="m365_evidence_agent",
            tier="tier_1",
            description=(
                "Retrieve delegated Microsoft 365 evidence from mail, calendars, "
                "Teams, OneDrive, and SharePoint through the governed M365 Gateway."
            ),
            prompt_ref=prompt_refs["m365_evidence_agent"],
            capability_refs=["capability:m365-delegated-evidence"],
            gateway_url=args.m365_gateway_url,
            gateway_target_id=targets["m365"]["id"],
            gateway_target_name=targets["m365"]["name"],
            server_id="m365-mcp-server",
        )
    ]
    if args.document_gateway_url:
        records.append(
            _profile(
                agent_type="document_intelligence_agent",
                tier="tier_2",
                description=(
                    "Analyze authorized PDF, DOCX, PPTX, XLSX, image, comparison, "
                    "and audit evidence through Document Intelligence."
                ),
                prompt_ref=prompt_refs["document_intelligence_agent"],
                capability_refs=[
                    "capability:document-structure",
                    "capability:document-text-retrieval",
                    "capability:document-visual-evidence",
                    "capability:document-structured-data",
                    "capability:document-comparison",
                    "capability:document-audit",
                ],
                gateway_url=args.document_gateway_url,
                gateway_target_id=targets["document"]["id"],
                gateway_target_name=targets["document"]["name"],
                server_id="document-intelligence-mcp-server",
                trusted_arguments={
                    "artifact_ids": "authorized_artifact_ids",
                    "invocation_id": "invocation_id",
                    "request": "request",
                    "runtime_config": "runtime_config",
                },
                max_turns=12,
                timeout_seconds=900,
            )
        )
    if args.web_gateway_url:
        records.append(
            _profile(
                agent_type="web_research_agent",
                tier="tier_1",
                description=(
                    "Retrieve current public-web evidence with preserved citations "
                    "through the governed Web Grounding Gateway."
                ),
                prompt_ref=prompt_refs["web_research_agent"],
                capability_refs=["capability:web.public_grounding"],
                gateway_url=args.web_gateway_url,
                gateway_target_id=targets["web"]["id"],
                gateway_target_name=targets["web"]["name"],
                server_id="web-grounding-mcp-server",
            )
        )
    return records


def _delete_obsolete_records(client: Any, *, registry_id: str) -> None:
    for item in _pages(
        client,
        "list_registry_records",
        "registryRecords",
        registryId=registry_id,
        maxResults=100,
    ):
        if item.get("name") not in OBSOLETE_RECORD_NAMES:
            continue
        client.delete_registry_record(
            registryId=registry_id,
            recordId=item["recordId"],
        )


def _ensure_record(
    client: Any,
    *,
    registry_id: str,
    profile: dict[str, Any],
    environment: str,
) -> str:
    name = profile["agent_type"]
    descriptor = {"custom": {"data": json.dumps(profile, sort_keys=True)}}
    existing = next(
        (
            item
            for item in _pages(
                client,
                "list_registry_records",
                "registryRecords",
                registryId=registry_id,
                maxResults=100,
            )
            if item.get("name") == name
        ),
        None,
    )
    if existing is None:
        response = client.create_registry_record(
            registryId=registry_id,
            name=name,
            displayName=name.replace("_", " ").title(),
            description=profile["description"],
            recordType="CUSTOM",
            descriptors=descriptor,
            recordVersion="1.0",
            tags={"Application": "GWen", "Environment": environment},
        )
        record_id = response["recordArn"].rsplit("/", 1)[-1]
        _wait_record_approved(client, registry_id, record_id)
        return record_id

    current = client.get_registry_record(
        registryId=registry_id,
        recordId=existing["recordId"],
    )
    if (
        current.get("descriptors") == descriptor
        and current.get("description") == profile["description"]
        and current.get("status") == "APPROVED"
    ):
        return existing["recordId"]
    client.update_registry_record(
        registryId=registry_id,
        recordId=existing["recordId"],
        description={"optionalValue": profile["description"]},
        recordType="CUSTOM",
        descriptors={
            "optionalValue": {
                "custom": {
                    "optionalValue": {
                        "data": {
                            "optionalValue": json.dumps(profile, sort_keys=True)
                        }
                    }
                }
            }
        },
        recordVersion="1.0",
    )
    _wait_record_approved(client, registry_id, existing["recordId"])
    return existing["recordId"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--environment", default="dev")
    parser.add_argument("--registry-id", required=True)
    parser.add_argument("--gateway-id", required=True)
    parser.add_argument("--m365-gateway-url", required=True)
    parser.add_argument("--m365-target-id", required=True)
    parser.add_argument("--document-gateway-url", default="")
    parser.add_argument("--document-target-id", default="")
    parser.add_argument("--web-gateway-url", default="")
    parser.add_argument("--web-target-id", default="")
    parser.add_argument("--m365-prompt-ref", required=True)
    parser.add_argument("--document-prompt-ref", required=True)
    parser.add_argument("--web-prompt-ref", required=True)
    args = parser.parse_args()

    client = boto3.client("agent-registry-control", region_name=args.region)
    gateway_client = boto3.client("bedrock-agentcore-control", region_name=args.region)
    registry_id = args.registry_id
    _wait_registry_ready(client, registry_id)
    _delete_obsolete_records(client, registry_id=registry_id)
    targets = {
        "m365": _gateway_target(
            gateway_client,
            gateway_id=args.gateway_id,
            target_id=args.m365_target_id,
        )
    }
    if args.document_gateway_url:
        if not args.document_target_id:
            raise ValueError("--document-target-id is required when Document is enabled")
        targets["document"] = _gateway_target(
            gateway_client,
            gateway_id=args.gateway_id,
            target_id=args.document_target_id,
        )
    if args.web_gateway_url:
        if not args.web_target_id:
            raise ValueError("--web-target-id is required when Web is enabled")
        targets["web"] = _gateway_target(
            gateway_client,
            gateway_id=args.gateway_id,
            target_id=args.web_target_id,
        )
    for profile in _desired_records(
        args,
        {
            "m365_evidence_agent": args.m365_prompt_ref,
            "document_intelligence_agent": args.document_prompt_ref,
            "web_research_agent": args.web_prompt_ref,
        },
        targets,
    ):
        _ensure_record(
            client,
            registry_id=registry_id,
            profile=profile,
            environment=args.environment,
        )
    print(json.dumps({"registry_id": registry_id}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Agent Registry reconciliation failed: {exc}", file=sys.stderr)
        raise

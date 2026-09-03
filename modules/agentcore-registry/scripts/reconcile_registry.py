#!/usr/bin/env python3
from __future__ import annotations

import argparse
import time
from typing import Any, Iterator

import boto3


def pages(client: Any, operation: str, result_key: str, **kwargs: Any) -> Iterator[Any]:
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


def wait_ready(client: Any, registry_id: str) -> None:
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", required=True)
    parser.add_argument("--profile", default="")
    parser.add_argument("--name", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--parameter-name", required=True)
    args = parser.parse_args()

    session = boto3.Session(
        profile_name=args.profile or None,
        region_name=args.region,
    )
    client = session.client("agent-registry-control")
    existing = next(
        (
            item
            for item in pages(client, "list_registries", "registries", maxResults=100)
            if item.get("name") == args.name
        ),
        None,
    )
    if existing is None:
        response = client.create_registry(
            name=args.name,
            description=args.description,
            discoveryConfiguration={"authorizerType": "AWS_IAM"},
            approvalConfiguration={"autoApprovalRules": ["APPROVE_ALL"]},
            tags={"Application": "GWen", "Environment": args.environment},
        )
        registry_id = response["registryArn"].rsplit("/", 1)[-1]
    else:
        registry_id = existing["registryId"]
    wait_ready(client, registry_id)

    session.client("ssm").put_parameter(
        Name=args.parameter_name,
        Type="String",
        Value=registry_id,
        Overwrite=True,
        Description="GWen Agent Registry identifier",
    )
    print(registry_id)


if __name__ == "__main__":
    main()

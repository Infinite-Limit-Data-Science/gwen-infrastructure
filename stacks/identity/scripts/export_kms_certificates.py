#!/usr/bin/env python3
"""Export Entra-compatible X.509 certificates for AWS KMS signing keys.

The private keys remain in KMS. This utility retrieves each public key, builds
an X.509 certificate around it, and asks KMS to self-sign the certificate. It
also emits the base64url SHA-256 thumbprint Entra expects in x5t#S256.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import textwrap


SHA256_WITH_RSA_ENCRYPTION_OID = "1.2.840.113549.1.1.11"
COMMON_NAME_OID = "2.5.4.3"
KMS_SIGNING_ALGORITHM = "RSASSA_PKCS1_V1_5_SHA_256"


class ExportError(RuntimeError):
    """Raised when a certificate cannot be exported safely."""


def _der_length(length: int) -> bytes:
    if length < 0:
        raise ValueError("DER length cannot be negative")
    if length < 128:
        return bytes((length,))
    encoded = length.to_bytes((length.bit_length() + 7) // 8, "big")
    return bytes((0x80 | len(encoded),)) + encoded


def _der(tag: int, content: bytes) -> bytes:
    return bytes((tag,)) + _der_length(len(content)) + content


def _der_sequence(*values: bytes) -> bytes:
    return _der(0x30, b"".join(values))


def _der_set(*values: bytes) -> bytes:
    return _der(0x31, b"".join(values))


def _der_integer(value: int) -> bytes:
    if value < 0:
        raise ValueError("Only non-negative DER integers are supported")
    encoded = value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")
    if encoded[0] & 0x80:
        encoded = b"\x00" + encoded
    return _der(0x02, encoded)


def _base128(value: int) -> bytes:
    if value < 0:
        raise ValueError("OID components cannot be negative")
    encoded = [value & 0x7F]
    value >>= 7
    while value:
        encoded.append(0x80 | (value & 0x7F))
        value >>= 7
    return bytes(reversed(encoded))


def _der_oid(value: str) -> bytes:
    components = [int(component) for component in value.split(".")]
    if len(components) < 2 or components[0] not in (0, 1, 2):
        raise ValueError(f"Invalid OID: {value}")
    if components[0] < 2 and components[1] > 39:
        raise ValueError(f"Invalid OID: {value}")
    encoded = _base128(40 * components[0] + components[1])
    encoded += b"".join(_base128(component) for component in components[2:])
    return _der(0x06, encoded)


def _der_null() -> bytes:
    return _der(0x05, b"")


def _der_utf8_string(value: str) -> bytes:
    return _der(0x0C, value.encode("utf-8"))


def _der_bit_string(value: bytes) -> bytes:
    return _der(0x03, b"\x00" + value)


def _der_time(value: datetime) -> bytes:
    value = value.astimezone(timezone.utc)
    if 1950 <= value.year <= 2049:
        return _der(0x17, value.strftime("%y%m%d%H%M%SZ").encode("ascii"))
    return _der(0x18, value.strftime("%Y%m%d%H%M%SZ").encode("ascii"))


def _algorithm_identifier() -> bytes:
    return _der_sequence(_der_oid(SHA256_WITH_RSA_ENCRYPTION_OID), _der_null())


def _distinguished_name(common_name: str) -> bytes:
    attribute = _der_sequence(
        _der_oid(COMMON_NAME_OID),
        _der_utf8_string(common_name),
    )
    return _der_sequence(_der_set(attribute))


def _build_tbs_certificate(
    public_key_der: bytes,
    common_name: str,
    valid_days: int,
) -> bytes:
    if not public_key_der.startswith(b"\x30"):
        raise ExportError("KMS returned an invalid DER SubjectPublicKeyInfo value")

    now = datetime.now(timezone.utc).replace(microsecond=0)
    not_before = now - timedelta(minutes=5)
    not_after = now + timedelta(days=valid_days)
    name = _distinguished_name(common_name)
    serial_number = max(1, int.from_bytes(secrets.token_bytes(16), "big") >> 1)

    return _der_sequence(
        _der(0xA0, _der_integer(2)),  # X.509 version 3
        _der_integer(serial_number),
        _algorithm_identifier(),
        name,
        _der_sequence(_der_time(not_before), _der_time(not_after)),
        name,
        public_key_der,
    )


def _build_certificate(tbs_certificate: bytes, signature: bytes) -> bytes:
    return _der_sequence(
        tbs_certificate,
        _algorithm_identifier(),
        _der_bit_string(signature),
    )


def _run(command: list[str]) -> str:
    try:
        completed = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError as exc:
        raise ExportError(f"Required executable was not found: {command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or "unknown command error"
        raise ExportError(f"Command failed: {' '.join(command)}\n{detail}") from exc
    return completed.stdout.strip()


def _terraform_output(terraform_bin: str, root_dir: Path, output_name: str) -> str:
    value = _run(
        [
            terraform_bin,
            f"-chdir={root_dir}",
            "output",
            "-raw",
            output_name,
        ]
    )
    if not value:
        raise ExportError(f"Terraform output {output_name!r} is empty")
    return value


class KmsClient:
    def __init__(self, aws_bin: str, profile: str | None, region: str) -> None:
        self._prefix = [aws_bin]
        if profile:
            self._prefix.extend(("--profile", profile))
        self._prefix.extend(("--region", region, "--no-cli-pager"))

    def _json(self, arguments: list[str]) -> dict[str, object]:
        raw = _run([*self._prefix, *arguments, "--output", "json"])
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ExportError("AWS CLI returned malformed JSON") from exc
        if not isinstance(value, dict):
            raise ExportError("AWS CLI returned an unexpected response")
        return value

    def public_key(self, key_arn: str) -> bytes:
        response = self._json(["kms", "get-public-key", "--key-id", key_arn])
        key_usage = response.get("KeyUsage")
        key_spec = response.get("KeySpec") or response.get("CustomerMasterKeySpec")
        algorithms = response.get("SigningAlgorithms")
        encoded_key = response.get("PublicKey")

        if key_usage != "SIGN_VERIFY":
            raise ExportError(f"KMS key {key_arn} is not a SIGN_VERIFY key")
        if not isinstance(key_spec, str) or not key_spec.startswith("RSA_"):
            raise ExportError(f"KMS key {key_arn} is not an RSA signing key")
        if not isinstance(algorithms, list) or KMS_SIGNING_ALGORITHM not in algorithms:
            raise ExportError(
                f"KMS key {key_arn} does not support {KMS_SIGNING_ALGORITHM}"
            )
        if not isinstance(encoded_key, str):
            raise ExportError(f"KMS key {key_arn} did not return a public key")
        try:
            return base64.b64decode(encoded_key, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise ExportError(f"KMS key {key_arn} returned invalid base64") from exc

    def sign(self, key_arn: str, message_path: Path) -> bytes:
        response = self._json(
            [
                "kms",
                "sign",
                "--key-id",
                key_arn,
                "--message",
                f"fileb://{message_path}",
                "--message-type",
                "RAW",
                "--signing-algorithm",
                KMS_SIGNING_ALGORITHM,
            ]
        )
        encoded_signature = response.get("Signature")
        if not isinstance(encoded_signature, str):
            raise ExportError(f"KMS key {key_arn} did not return a signature")
        try:
            return base64.b64decode(encoded_signature, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise ExportError(f"KMS key {key_arn} returned an invalid signature") from exc

    def verify(
        self,
        key_arn: str,
        message_path: Path,
        signature_path: Path,
    ) -> None:
        response = self._json(
            [
                "kms",
                "verify",
                "--key-id",
                key_arn,
                "--message",
                f"fileb://{message_path}",
                "--message-type",
                "RAW",
                "--signature",
                f"fileb://{signature_path}",
                "--signing-algorithm",
                KMS_SIGNING_ALGORITHM,
            ]
        )
        if response.get("SignatureValid") is not True:
            raise ExportError(f"KMS failed to verify the certificate for {key_arn}")


def _pem_certificate(certificate_der: bytes) -> str:
    encoded = base64.b64encode(certificate_der).decode("ascii")
    body = "\n".join(textwrap.wrap(encoded, width=64))
    return f"-----BEGIN CERTIFICATE-----\n{body}\n-----END CERTIFICATE-----\n"


def _thumbprint(certificate_der: bytes) -> str:
    digest = hashlib.sha256(certificate_der).digest()
    return base64.urlsafe_b64encode(digest).decode("ascii").rstrip("=")


def _export_certificate(
    kms: KmsClient,
    key_arn: str,
    common_name: str,
    output_name: str,
    valid_days: int,
    staging_dir: Path,
) -> tuple[Path, Path]:
    public_key = kms.public_key(key_arn)
    tbs_certificate = _build_tbs_certificate(public_key, common_name, valid_days)
    tbs_path = staging_dir / f"{output_name}.tbs.der"
    signature_path = staging_dir / f"{output_name}.signature"
    tbs_path.write_bytes(tbs_certificate)

    signature = kms.sign(key_arn, tbs_path)
    signature_path.write_bytes(signature)
    kms.verify(key_arn, tbs_path, signature_path)

    certificate_der = _build_certificate(tbs_certificate, signature)
    certificate_path = staging_dir / f"{output_name}.crt"
    thumbprint_path = staging_dir / f"{output_name}.x5t-s256"
    certificate_path.write_text(_pem_certificate(certificate_der), encoding="ascii")
    thumbprint_path.write_text(_thumbprint(certificate_der), encoding="ascii")
    return certificate_path, thumbprint_path


def _arguments() -> argparse.Namespace:
    root_dir = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Export Entra-compatible certificates for the Identity KMS keys."
    )
    parser.add_argument(
        "--root-dir",
        type=Path,
        default=root_dir,
        help="Identity Terraform root (default: parent of this script directory).",
    )
    parser.add_argument(
        "--cert-dir",
        type=Path,
        default=Path(os.environ.get("CERT_DIR", root_dir / ".certs")),
        help="Output directory (default: <identity-root>/.certs).",
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("AWS_PROFILE"),
        help="AWS CLI profile (default: AWS_PROFILE or the CLI credential chain).",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1")),
        help="AWS region (default: AWS_REGION, AWS_DEFAULT_REGION, or us-east-1).",
    )
    parser.add_argument(
        "--terraform-bin",
        default=os.environ.get("TERRAFORM_BIN", "terraform"),
        help="Terraform executable (default: TERRAFORM_BIN or terraform).",
    )
    parser.add_argument(
        "--aws-bin",
        default=os.environ.get("AWS_CLI_BIN", "aws"),
        help="AWS CLI executable (default: AWS_CLI_BIN or aws).",
    )
    parser.add_argument(
        "--agent-key-arn",
        help="Agent API KMS key ARN; defaults to the Terraform output.",
    )
    parser.add_argument(
        "--m365-key-arn",
        help="M365 KMS key ARN; defaults to the Terraform output.",
    )
    parser.add_argument(
        "--valid-days",
        type=int,
        default=825,
        help="Certificate validity in days (default: 825).",
    )
    return parser.parse_args()


def main() -> int:
    args = _arguments()
    if args.valid_days <= 0:
        raise ExportError("--valid-days must be greater than zero")

    root_dir = args.root_dir.expanduser().resolve()
    cert_dir = args.cert_dir.expanduser().resolve()
    agent_key_arn = args.agent_key_arn or _terraform_output(
        args.terraform_bin,
        root_dir,
        "agent_api_signing_key_arn",
    )
    m365_key_arn = args.m365_key_arn or _terraform_output(
        args.terraform_bin,
        root_dir,
        "m365_signing_key_arn",
    )

    cert_dir.mkdir(parents=True, exist_ok=True)
    kms = KmsClient(args.aws_bin, args.profile, args.region)
    with tempfile.TemporaryDirectory(prefix=".kms-certificates-", dir=cert_dir) as temporary:
        staging_dir = Path(temporary)
        outputs = [
            _export_certificate(
                kms,
                agent_key_arn,
                "GuideWell Agent API AgentCore OBO",
                "guidewell-agent-api-kms",
                args.valid_days,
                staging_dir,
            ),
            _export_certificate(
                kms,
                m365_key_arn,
                "GuideWell M365 MCP AgentCore OBO",
                "m365-mcp-kms",
                args.valid_days,
                staging_dir,
            ),
        ]
        for certificate_path, thumbprint_path in outputs:
            certificate_path.replace(cert_dir / certificate_path.name)
            thumbprint_path.replace(cert_dir / thumbprint_path.name)

    print(f"Generated KMS-backed public certificates in {cert_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc

#!/usr/bin/env python3
"""
Generate signed activation JSON + QR for Receipt Scanner.

Usage:
  python tools/generate_activation_qr.py ^
    --company-code ACME-UK-001 ^
    --exp 2027-12-31 ^
    --kid k1 ^
    --private-seed-b64 <BASE64_OR_BASE64URL_32_BYTE_SEED> ^
    --plan pro ^
    --features quality_scan,export_zip ^
    --out-dir .\\activation_out
"""

from __future__ import annotations

import argparse
import base64
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import List

import qrcode
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64_flexible_decode(value: str) -> bytes:
    v = value.strip().replace("-", "+").replace("_", "/")
    pad = len(v) % 4
    if pad:
        v += "=" * (4 - pad)
    return base64.b64decode(v)


def parse_features(raw: str) -> List[str]:
    if not raw.strip():
        return []
    return [x.strip() for x in raw.split(",") if x.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate activation QR.")
    parser.add_argument("--company-code", required=True)
    parser.add_argument("--exp", required=True, help="YYYY-MM-DD")
    parser.add_argument("--kid", required=True)
    parser.add_argument("--private-seed-b64", required=True)
    parser.add_argument("--plan", default="standard")
    parser.add_argument("--features", default="")
    parser.add_argument("--out-dir", default="activation_out")
    parser.add_argument("--db-path", default="activation_out/activation_records.db")
    args = parser.parse_args()

    seed = b64_flexible_decode(args.private_seed_b64)
    if len(seed) != 32:
        raise ValueError("Private seed must decode to exactly 32 bytes.")

    private_key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    public_key = private_key.public_key()
    public_key_bytes = public_key.public_bytes(
        encoding=Encoding.Raw, format=PublicFormat.Raw
    )

    payload = {
        "kid": args.kid.strip(),
        "company_code": args.company_code.strip(),
        "plan": args.plan.strip(),
        "exp": args.exp.strip(),
        "features": parse_features(args.features),
    }
    payload_bytes = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode(
        "utf-8"
    )
    signature = private_key.sign(payload_bytes)

    activation = {
        "payload_b64": b64url_encode(payload_bytes),
        "sig_b64": b64url_encode(signature),
        "alg": "Ed25519",
    }

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    safe_company = "".join(
        c for c in args.company_code.strip() if c.isalnum() or c in ("-", "_")
    )
    base = f"activation_{safe_company}_{args.exp.strip()}"
    json_path = out_dir / f"{base}.json"
    qr_path = out_dir / f"{base}.png"
    pub_path = out_dir / "public_key_for_app.txt"

    json_text = json.dumps(activation, separators=(",", ":"), ensure_ascii=True)
    json_path.write_text(json_text, encoding="utf-8")

    qr_img = qrcode.make(json_text)
    qr_img.save(qr_path)

    pub_path.write_text(
        f"kid={args.kid.strip()}\npublic_key_b64={b64url_encode(public_key_bytes)}\n",
        encoding="utf-8",
    )

    _save_record(
        db_path=Path(args.db_path),
        company_code=args.company_code.strip(),
        exp=args.exp.strip(),
        kid=args.kid.strip(),
        plan=args.plan.strip(),
        features=parse_features(args.features),
        payload_b64=activation["payload_b64"],
        sig_b64=activation["sig_b64"],
        json_path=str(json_path),
        qr_path=str(qr_path),
    )

    print(f"Activation JSON: {json_path}")
    print(f"Activation QR:   {qr_path}")
    print(f"Public key file: {pub_path}")
    print(f"Activation DB:   {Path(args.db_path)}")
    print("")
    print("Set this in app _publicKeysByKid map:")
    print(f"'{args.kid.strip()}': '{b64url_encode(public_key_bytes)}'")


def _save_record(
    db_path: Path,
    company_code: str,
    exp: str,
    kid: str,
    plan: str,
    features: List[str],
    payload_b64: str,
    sig_b64: str,
    json_path: str,
    qr_path: str,
) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS activation_records (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              issued_at_utc TEXT NOT NULL,
              company_code TEXT NOT NULL,
              exp TEXT NOT NULL,
              kid TEXT NOT NULL,
              plan TEXT NOT NULL,
              features_json TEXT NOT NULL,
              payload_b64 TEXT NOT NULL,
              sig_b64 TEXT NOT NULL,
              json_path TEXT NOT NULL,
              qr_path TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            INSERT INTO activation_records (
              issued_at_utc, company_code, exp, kid, plan, features_json,
              payload_b64, sig_b64, json_path, qr_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                datetime.now(timezone.utc).isoformat(),
                company_code,
                exp,
                kid,
                plan,
                json.dumps(features, separators=(",", ":"), ensure_ascii=True),
                payload_b64,
                sig_b64,
                json_path,
                qr_path,
            ),
        )
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric import ed25519


def b64_flexible_decode(value: str) -> bytes:
    v = value.strip().replace("-", "+").replace("_", "/")
    pad = len(v) % 4
    if pad:
        v += "=" * (4 - pad)
    return base64.b64decode(v)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--activation-json", required=True)
    p.add_argument("--public-key-b64", required=True)
    args = p.parse_args()

    activation = json.loads(Path(args.activation_json).read_text(encoding="utf-8"))
    payload_b64 = activation["payload_b64"]
    sig_b64 = activation["sig_b64"]

    payload = b64_flexible_decode(payload_b64)
    sig = b64_flexible_decode(sig_b64)
    pub = b64_flexible_decode(args.public_key_b64)

    public_key = ed25519.Ed25519PublicKey.from_public_bytes(pub)
    try:
        public_key.verify(sig, payload)
        print("OK: signature matches public key.")
        print(f"Payload: {payload.decode('utf-8')}")
    except Exception:
        print("FAIL: signature mismatch.")


if __name__ == "__main__":
    main()


#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox

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


def save_record(
    db_path: Path,
    company_code: str,
    exp: str,
    kid: str,
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
              issued_at_utc, company_code, exp, kid, payload_b64, sig_b64, json_path, qr_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                datetime.now(timezone.utc).isoformat(),
                company_code,
                exp,
                kid,
                payload_b64,
                sig_b64,
                json_path,
                qr_path,
            ),
        )
        conn.commit()
    finally:
        conn.close()


def generate() -> None:
    company_code = company_var.get().strip()
    exp = exp_var.get().strip()
    kid = kid_var.get().strip() or "k1"
    seed_b64 = seed_var.get().strip()
    out_dir = Path(out_var.get().strip() or "activation_out")

    if not company_code or not exp or not seed_b64:
        messagebox.showerror("Missing fields", "Company code, Expiry, and Private seed are required.")
        return
    if datetime.strptime(exp, "%Y-%m-%d") is None:  # format check
        return

    try:
        seed = b64_flexible_decode(seed_b64)
        if len(seed) != 32:
            raise ValueError("Private seed must decode to 32 bytes.")

        private_key = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
        public_key = private_key.public_key()
        public_key_bytes = public_key.public_bytes(encoding=Encoding.Raw, format=PublicFormat.Raw)

        payload = {
            "kid": kid,
            "company_code": company_code,
            "exp": exp,
        }
        payload_bytes = json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
        signature = private_key.sign(payload_bytes)

        activation = {
            "payload_b64": b64url_encode(payload_bytes),
            "sig_b64": b64url_encode(signature),
            "alg": "Ed25519",
        }

        out_dir.mkdir(parents=True, exist_ok=True)
        safe_company = "".join(c for c in company_code if c.isalnum() or c in ("-", "_"))
        base = f"activation_{safe_company}_{exp}"
        json_path = out_dir / f"{base}.json"
        qr_path = out_dir / f"{base}.png"
        pub_path = out_dir / "public_key_for_app.txt"
        db_path = out_dir / "activation_records.db"

        json_text = json.dumps(activation, separators=(",", ":"), ensure_ascii=True)
        json_path.write_text(json_text, encoding="utf-8")
        qrcode.make(json_text).save(qr_path)
        pub_path.write_text(f"kid={kid}\npublic_key_b64={b64url_encode(public_key_bytes)}\n", encoding="utf-8")

        save_record(
            db_path=db_path,
            company_code=company_code,
            exp=exp,
            kid=kid,
            payload_b64=activation["payload_b64"],
            sig_b64=activation["sig_b64"],
            json_path=str(json_path),
            qr_path=str(qr_path),
        )

        result_var.set(
            f"Generated:\nJSON: {json_path}\nQR: {qr_path}\nDB: {db_path}\n\n"
            f"Put this in app _publicKeysByKid:\n'{kid}': '{b64url_encode(public_key_bytes)}'"
        )
    except Exception as e:
        messagebox.showerror("Generation failed", str(e))


def pick_out_dir() -> None:
    chosen = filedialog.askdirectory(initialdir=out_var.get().strip() or ".")
    if chosen:
        out_var.set(chosen)

def generate_seed() -> None:
    seed_var.set(b64url_encode(__import__("os").urandom(32)))


root = tk.Tk()
root.title("Activation Key Generator")
root.geometry("760x520")

company_var = tk.StringVar()
exp_var = tk.StringVar()
kid_var = tk.StringVar(value="k1")
seed_var = tk.StringVar()
out_var = tk.StringVar(value="activation_out")
result_var = tk.StringVar()

frm = tk.Frame(root, padx=14, pady=12)
frm.pack(fill="both", expand=True)

tk.Label(frm, text="Company code").grid(row=0, column=0, sticky="w")
tk.Entry(frm, textvariable=company_var, width=60).grid(row=0, column=1, sticky="we", pady=4)

tk.Label(frm, text="Expiry (YYYY-MM-DD)").grid(row=1, column=0, sticky="w")
tk.Entry(frm, textvariable=exp_var, width=60).grid(row=1, column=1, sticky="we", pady=4)

tk.Label(frm, text="Key ID (kid)").grid(row=2, column=0, sticky="w")
tk.Entry(frm, textvariable=kid_var, width=60).grid(row=2, column=1, sticky="we", pady=4)

tk.Label(frm, text="Private seed b64 (32 bytes)").grid(row=3, column=0, sticky="w")
seed_row = tk.Frame(frm)
seed_row.grid(row=3, column=1, sticky="we", pady=4)
tk.Entry(seed_row, textvariable=seed_var, width=48, show="*").pack(
    side="left", fill="x", expand=True
)
tk.Button(seed_row, text="Generate Seed", command=generate_seed).pack(
    side="left", padx=6
)

tk.Label(frm, text="Output folder").grid(row=4, column=0, sticky="w")
out_row = tk.Frame(frm)
out_row.grid(row=4, column=1, sticky="we", pady=4)
tk.Entry(out_row, textvariable=out_var, width=48).pack(side="left", fill="x", expand=True)
tk.Button(out_row, text="Browse", command=pick_out_dir).pack(side="left", padx=6)

tk.Button(frm, text="Generate Activation", command=generate, height=2).grid(
    row=5, column=0, columnspan=2, sticky="we", pady=10
)

tk.Label(frm, text="Result").grid(row=6, column=0, sticky="nw")
result_box = tk.Text(frm, height=14, wrap="word")
result_box.grid(row=6, column=1, sticky="nsew")


def sync_result(*_: object) -> None:
    result_box.delete("1.0", "end")
    result_box.insert("1.0", result_var.get())


result_var.trace_add("write", sync_result)
frm.columnconfigure(1, weight=1)
frm.rowconfigure(6, weight=1)

root.mainloop()

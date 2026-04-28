#!/usr/bin/env python3
"""
Generate Scripts/l10n_bundle.json — full translations for all Swift String(localized:) keys.
Uses Google Translate via deep-translator (requires network).

Run from repo Wist folder:
  python3 Scripts/machine_translate_bundle.py

Locale mapping: zh-CN API result → Xcode key "zh-Hans"
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

TARGETS = [
    ("es", "es"),
    ("zh-Hans", "zh-CN"),
    ("hi", "hi"),
    ("ar", "ar"),
    ("fr", "fr"),
    ("he", "he"),
]


def main() -> None:
    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print("pip install deep-translator", file=sys.stderr)
        sys.exit(1)

    keys_path = SCRIPT_DIR / "_keys_snapshot.json"
    if not keys_path.exists():
        print("Missing _keys_snapshot.json — run key extraction first.", file=sys.stderr)
        sys.stderr.flush()
        sys.exit(1)

    keys: list[str] = json.loads(keys_path.read_text(encoding="utf-8"))
    bundle: dict[str, dict[str, str]] = {}

    total = len(keys) * len(TARGETS)
    n = 0
    for ki, en in enumerate(keys):
        bundle[en] = {}
        for xcode_loc, gt_loc in TARGETS:
            n += 1
            try:
                t = GoogleTranslator(source="en", target=gt_loc)
                out = t.translate(en)
                bundle[en][xcode_loc] = out
            except Exception as e:
                print(f"FAIL [{n}/{total}] {en[:50]}… → {xcode_loc}: {e}", file=sys.stderr)
                bundle[en][xcode_loc] = en
            time.sleep(0.12)
        if (ki + 1) % 10 == 0:
            print(f"… {ki + 1}/{len(keys)} keys", flush=True)

    out_path = SCRIPT_DIR / "l10n_bundle.json"
    out_path.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {out_path} ({len(bundle)} keys).")


if __name__ == "__main__":
    main()

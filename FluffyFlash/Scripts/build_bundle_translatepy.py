#!/usr/bin/env python3
"""
Build l10n_bundle.json for all String(localized:) keys using translatepy (avoids
some Google SSL issues; supports Hebrew, etc.).

  cd Wist && python3 Scripts/build_bundle_translatepy.py

Requires: pip install translatepy

Checkpoint: saves Scripts/l10n_bundle.partial.json after each key (resume on rerun).
Timeouts: each translate call is wrapped (default 28s) to avoid hangs.
"""

from __future__ import annotations

import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeoutError
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PARTIAL_PATH = SCRIPT_DIR / "l10n_bundle.partial.json"
OUT_PATH = SCRIPT_DIR / "l10n_bundle.json"

# translatepy destination language names (Google-backed services)
LANGS = [
    ("es", "Spanish"),
    ("zh-Hans", "Chinese (Simplified)"),
    ("hi", "Hindi"),
    ("ar", "Arabic"),
    ("fr", "French"),
    ("he", "Hebrew"),
]

TRANSLATE_TIMEOUT_SEC = 28.0


def unswift_string(raw: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            n = raw[i + 1]
            if n == "n":
                out.append("\n")
                i += 2
                continue
            if n == "t":
                out.append("\t")
                i += 2
                continue
            if n == "\\":
                out.append("\\")
                i += 2
                continue
            if n == '"':
                out.append('"')
                i += 2
                continue
        out.append(raw[i])
        i += 1
    return "".join(out)


def extract_keys(swift_root: Path) -> list[str]:
    import re

    keys: list[str] = []
    seen: set[str] = set()
    pattern1 = re.compile(r'String\(localized:\s*"((?:\\.|[^"\\])*)"\s*\)')
    pattern3 = re.compile(r'String\(format:\s*String\(localized:\s*"((?:\\.|[^"\\])*)"\)')
    for path in sorted(swift_root.rglob("*.swift")):
        if "ThirdParty" in str(path):
            continue
        text = path.read_text(encoding="utf-8")
        for r in (pattern1, pattern3):
            for m in r.finditer(text):
                s = unswift_string(m.group(1))
                if s not in seen:
                    seen.add(s)
                    keys.append(s)
    return keys


def _translate_call(translator, text: str, tp_lang: str):
    return translator.translate(text, tp_lang)


def translate_with_timeout(translator, text: str, tp_lang: str) -> str:
    last_err: Exception | None = None
    for attempt in range(5):
        try:
            with ThreadPoolExecutor(max_workers=1) as ex:
                fut = ex.submit(_translate_call, translator, text, tp_lang)
                result = fut.result(timeout=TRANSLATE_TIMEOUT_SEC)
            out = getattr(result, "result", None) or str(result)
            return out
        except FuturesTimeoutError as e:
            last_err = e
        except Exception as e:
            last_err = e
        time.sleep(1.2 * (attempt + 1))
    raise last_err or RuntimeError("translate failed")


def key_complete(row: dict[str, str]) -> bool:
    return all(row.get(loc) for loc, _ in LANGS)


def load_partial() -> dict[str, dict[str, str]]:
    if not PARTIAL_PATH.exists():
        return {}
    try:
        data = json.loads(PARTIAL_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_partial(bundle: dict[str, dict[str, str]]) -> None:
    PARTIAL_PATH.write_text(
        json.dumps(bundle, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    try:
        from translatepy import Translator
    except ImportError:
        print("pip install translatepy", file=sys.stderr)
        sys.exit(1)

    swift_root = SCRIPT_DIR.parent / "Wist"
    keys_path = SCRIPT_DIR / "_keys_snapshot.json"

    keys = extract_keys(swift_root)
    keys_path.write_text(json.dumps(keys, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    bundle: dict[str, dict[str, str]] = load_partial()
    cache: dict[tuple[str, str], str] = {}
    translator = Translator()

    total_keys = len(keys)
    complete_before = sum(
        1 for k in keys if k in bundle and key_complete(bundle[k])
    )
    print(
        f"Resume: {complete_before}/{total_keys} keys complete in partial.",
        flush=True,
    )

    for en in keys:
        if en in bundle and key_complete(bundle[en]):
            continue

        row = bundle.get(en, {})
        for xcode_loc, tp_lang in LANGS:
            if row.get(xcode_loc):
                continue
            ck = (en, tp_lang)
            if ck in cache:
                row[xcode_loc] = cache[ck]
                bundle[en] = row
                continue
            last_err = None
            for attempt in range(5):
                try:
                    text = translate_with_timeout(translator, en, tp_lang)
                    if not text or not str(text).strip():
                        text = en
                    cache[ck] = text
                    row[xcode_loc] = text
                    bundle[en] = row
                    break
                except Exception as e:
                    last_err = e
                    translator = Translator()
                    time.sleep(1.5 * (attempt + 1))
            else:
                print(
                    f"FAIL → {xcode_loc}: {en[:56]}… : {last_err}",
                    file=sys.stderr,
                )
                row[xcode_loc] = en
                bundle[en] = row

            time.sleep(0.06)

        save_partial(bundle)
        nk = sum(1 for k in keys if k in bundle and key_complete(bundle[k]))
        if nk % 10 == 0 or nk == total_keys:
            print(f"… checkpoint {nk}/{total_keys} keys", flush=True)

    OUT_PATH.write_text(
        json.dumps(bundle, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if PARTIAL_PATH.exists():
        PARTIAL_PATH.unlink()
    print(f"Wrote {OUT_PATH} ({len(bundle)} keys). Snapshot: {keys_path}")


if __name__ == "__main__":
    main()

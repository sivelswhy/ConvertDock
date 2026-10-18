#!/bin/bash
# Liste les clés de traduction absentes de Resources/fr.lproj/Localizable.strings.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
{
  grep -rhoE 'L\("([^"\\]|\\.)*"' Sources | sed -E 's/^L\("//; s/"$//'
  .build/debug/ConvertDock --l10n-keys
} | sort -u > /tmp/convertdock-keys.txt
python3 - "$@" <<'PY'
import re
strings = open("Resources/fr.lproj/Localizable.strings", encoding="utf-8").read()
have = set(m.replace('\\"', '"') for m in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', strings, re.M))
keys = [k.rstrip("\n").replace('\\"', '"') for k in open("/tmp/convertdock-keys.txt", encoding="utf-8")]
missing = [k for k in keys if k and k not in have]
for k in missing: print("manquant :", k)
print(f"{len(keys) - len(missing)}/{len(keys)} clés traduites")
raise SystemExit(1 if missing else 0)
PY

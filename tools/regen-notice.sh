#!/usr/bin/env bash
# Regenerate NOTICE + THIRD-PARTY-LICENSES.txt for a release, from what the
# released images contain: the controller, the proxy (built with
# `--features full`) and the edge, each scanned separately with cargo-about,
# then merged and rendered by gen-third-party-notice.py.
#
#   tools/regen-notice.sh ~/dev/zenoingress
#
# Needs cargo-about. The license allow-list is the source tree's about.toml.
set -euo pipefail
SRC="${1:?usage: $0 <zenoingress source tree>}"
OUT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$SRC"
cargo about generate --format json --all-features -o "$TMP/workspace.json"
cargo about generate --format json -m crates/zenoingress-controller/Cargo.toml -o "$TMP/controller.json"
cargo about generate --format json -m crates/zenoingress-proxy/Cargo.toml --features full -o "$TMP/proxy.json"
cargo about generate --format json -m crates/zenoingress-edge/Cargo.toml -o "$TMP/edge.json"

python3 - "$TMP" <<'PY'
import json, sys
tmp = sys.argv[1]
def key(c):
    return (c["package"]["name"], c["package"]["version"])
shipped = set()
for name in ("controller", "proxy", "edge"):
    shipped |= {key(c) for c in json.load(open(f"{tmp}/{name}.json"))["crates"]}
data = json.load(open(f"{tmp}/workspace.json"))
data["crates"] = [c for c in data["crates"] if key(c) in shipped]
for lic in data["licenses"]:
    lic["used_by"] = [u for u in lic["used_by"]
                      if (u["crate"]["name"], u["crate"]["version"]) in shipped]
data["licenses"] = [l for l in data["licenses"] if l["used_by"]]
json.dump(data, open(f"{tmp}/shipped.json", "w"))
print(f"crates in the released images: {len(shipped)}")
PY

python3 "$OUT/tools/gen-third-party-notice.py" "$TMP/shipped.json" "$OUT"

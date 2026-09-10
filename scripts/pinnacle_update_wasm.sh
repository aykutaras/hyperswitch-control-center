#!/usr/bin/env bash
# Regenerate public/hyperswitch/wasm from our hyperswitch fork, check it, and
# copy it into place. Commit the result yourself.
#
#   scripts/pinnacle_update_wasm.sh [hyperswitch-checkout] [connector]
#
#   hyperswitch-checkout  defaults to ../hyperswitch
#   connector             if given, the new WASM must return auth fields and at
#                         least one payment method for it
#
# The dashboard's getConnectorConfig runs Connector::from_str first, so a
# connector the WASM does not know cannot be configured even when
# ConnectorUtils.res lists it (hyperswitch-k8s DEPLOYMENT_GUIDE.md §10).
#
# Built inside Linux: Apple clang has no wasm32 backend, so `ring` cannot compile
# for wasm32-unknown-unknown on macOS. The features are upstream's Makefile target
# (dummy_connector,v1), which embed connector_configs/toml/development.toml.
set -euo pipefail

cd "$(dirname "$0")/.."

HS=$(cd "${1:-../hyperswitch}" && pwd)
CONNECTOR=${2:-}
DEST=public/hyperswitch/wasm
FILES="euclid.js euclid.d.ts euclid_bg.wasm euclid_bg.wasm.d.ts package.json"

fail() { echo "error: $*" >&2; exit 1; }

if [ -n "$CONNECTOR" ] && ! [[ "$CONNECTOR" =~ ^[a-z0-9_]+$ ]]; then
  fail "connector name must be lowercase letters, digits and underscores: '$CONNECTOR'"
fi
[ -z "$(git -C "$HS" status --porcelain)" ] \
  || fail "$HS has uncommitted changes; build the WASM from a commit"
[ -z "$CONNECTOR" ] || command -v node >/dev/null || fail "node is required to check '$CONNECTOR'"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo "==> building euclid_wasm from $HS ($(git -C "$HS" rev-parse --short HEAD))"
docker volume create hs-wasm-cache >/dev/null
docker run --rm \
  -v "$HS":/src:ro -v hs-wasm-cache:/cache -v "$OUT":/out \
  -e CARGO_HOME=/cache/cargo -e CARGO_TARGET_DIR=/cache/target -e CARGO_BUILD_JOBS=4 \
  public.ecr.aws/docker/library/rust:trixie bash -euo pipefail -c '
    export PATH=/cache/cargo/bin:$PATH
    apt-get update -qq && apt-get install -y -qq clang lld llvm >/dev/null
    rustup target add wasm32-unknown-unknown
    command -v wasm-pack >/dev/null || cargo install wasm-pack --version 0.15.0 --locked
    cd /src
    wasm-pack build --target web --out-dir /out --out-name euclid \
      crates/euclid_wasm -- --features dummy_connector,v1
  '

# Check 1: the new WASM must still export every function module.js calls that
# the current WASM provides.
python3 - "$OUT" "$DEST" <<'PY'
import re, sys
out, dest = sys.argv[1], sys.argv[2]
exports = lambda path: set(re.findall(r"^export function (\w+)", open(path).read(), re.M))
called = set(re.findall(r"wasm\.(\w+)\(", open("public/hyperswitch/module.js").read())) - {"default"}
current, new = exports(f"{dest}/euclid.js"), exports(f"{out}/euclid.js")
dropped = sorted((called & current) - new)
print(f"check 1: module.js calls {len(called)} functions; current WASM provides {len(called & current)}, new WASM {len(called & new)}")
if dropped:
    sys.exit(f"error: the new WASM drops functions the dashboard calls: {dropped}")
PY

# Check 2: the WASM itself must know the connector and its payment methods.
if [ -n "$CONNECTOR" ]; then
  cat >"$OUT/check.mjs" <<'JS'
import { readFileSync } from "node:fs";
import { initSync, getConnectorConfig } from "./euclid.js";
initSync({ module: readFileSync(new URL("./euclid_bg.wasm", import.meta.url)) });
const name = process.argv[2];
const plain = (v) => JSON.parse(JSON.stringify(v, (k, x) => (x instanceof Map ? Object.fromEntries(x) : x)));
const config = plain(getConnectorConfig(name));
const methods = Object.entries(config).filter(([, v]) => Array.isArray(v) && v.length).map(([k, v]) => `${k}:${v.length}`);
const auth = Object.keys(config.connector_auth || {});
console.log(`check 2: ${name} auth=${auth.join(",") || "none"} payment methods=${methods.join(" ") || "none"}`);
if (!auth.length || !methods.length) {
  console.error(`error: '${name}' has no auth fields or no payment methods in the WASM`);
  process.exit(1);
}
JS
  node "$OUT/check.mjs" "$CONNECTOR"
fi

for f in $FILES; do cp "$OUT/$f" "$DEST/$f"; done
echo "==> copied into $DEST"
git status --short -- "$DEST"
echo "Commit with: git add -f $DEST   (the directory's .gitignore is '*')"

#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORKOP_LIB="$ROOT_DIR/forkop/files/usr/lib"
GENERATOR="$FORKOP_LIB/singbox/generator.uc"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat >"$WORK_DIR/fixture.json" <<'JSON'
{
  "settings": {
    ".name": "settings",
    ".type": "settings",
    "config_path": "/tmp/sing-box/config.json",
    "dns_server": "1.1.1.1",
    "bootstrap_dns_server": "1.1.1.1",
    "service_listen_address": "127.0.0.1"
  },
  "section": [
    {
      ".name": "proxy",
      ".type": "section",
      "enabled": "1",
      "action": "outbound",
      "outbound_json": "{\"type\":\"direct\"}",
      "domain_suffix": [ "example.org" ]
    }
  ]
}
JSON

generate_for_version() {
  local version="$1"
  local output="$2"
  mkdir -p "$output.section-cache" "$output.rulesets"
  ucode -L "$FORKOP_LIB" "$GENERATOR" generate-config-fixture \
    "$WORK_DIR/fixture.json" "$output" "127.0.0.1" "0" "1" "" "$version"
}

generate_for_version "1.13.18-extended-2.6.5" "$WORK_DIR/sb113.json"
grep -Eq '"independent_cache"[[:space:]]*:[[:space:]]*true' "$WORK_DIR/sb113.json" ||
  fail "sing-box 1.13 must keep independent_cache for legacy semantics"

generate_for_version "1.14.0-extended-2.7.0" "$WORK_DIR/sb114.json"
if grep -Fq '"independent_cache"' "$WORK_DIR/sb114.json"; then
  fail "sing-box 1.14 must not receive deprecated independent_cache"
fi

generate_for_version "" "$WORK_DIR/unknown.json"
grep -Eq '"independent_cache"[[:space:]]*:[[:space:]]*true' "$WORK_DIR/unknown.json" ||
  fail "unknown sing-box version must preserve legacy behavior"

printf 'sing-box 1.14 independent_cache compatibility checks passed\n'

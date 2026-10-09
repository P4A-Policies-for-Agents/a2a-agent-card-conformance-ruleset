# Shared helpers for publish-examples.sh and cleanup-examples.sh. Source it; don't run it.
# Reads the Anypoint target from .env (copy .env.example), or from the environment if there is no
# .env. Never commit .env.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

if [ -f .env ]; then set -a; . ./.env; set +a; fi
: "${ANYPOINT_CLIENT_ID:?set ANYPOINT_CLIENT_ID in .env (copy .env.example)}"
: "${ANYPOINT_CLIENT_SECRET:?set ANYPOINT_CLIENT_SECRET in .env}"
: "${ANYPOINT_ORG_ID:?set ANYPOINT_ORG_ID (business group ID) in .env}"
ANYPOINT_HOST=${ANYPOINT_HOST:-anypoint.mulesoft.com}
EXAMPLES_VERSION=${EXAMPLES_VERSION:-1.0.0}
EXAMPLES_PREFIX=${EXAMPLES_PREFIX:-$(jq -r .assetId exchange.json)}
BASE_URL="https://$ANYPOINT_HOST"
command -v jq >/dev/null || fail "jq is required"

# Prints a bearer token for the connected app in .env.
token() {
  local resp
  resp=$(curl -sS -X POST "$BASE_URL/accounts/api/v2/oauth2/token" -d grant_type=client_credentials \
    --data-urlencode "client_id=$ANYPOINT_CLIENT_ID" --data-urlencode "client_secret=$ANYPOINT_CLIENT_SECRET")
  jq -re .access_token <<<"$resp" 2>/dev/null \
    || fail "token request to $ANYPOINT_HOST failed (wrong control plane? EU orgs use eu1.anypoint.mulesoft.com)"
}

# Prints one TSV line per example: assetId, name, description, fixture dir.
# Default: fixtures/good plus one bad fixture per rule. With $1 = all: every bad variant and scope fixture.
example_plan() {
  python3 -I - "$EXAMPLES_PREFIX" "${1:-}" <<'PY'
import os, re, sys
prefix, mode = sys.argv[1], sys.argv[2]
y = open("ruleset.yaml").read()
title = re.search(r"^profile:\s*(.+)$", y, re.M).group(1).strip()
sev = {}
for s in ("violation", "warning", "info"):
    m = re.search(rf"^{s}:\n((?:\s+- .+\n)+)", y, re.M)
    for r in re.findall(r"- (\S+)", m.group(1)) if m else []:
        sev[r] = s
bad = sorted(os.listdir("fixtures/bad"))

def row(asset, name, desc, d):
    print("\t".join([asset, name, desc, d]))

def expect(d, rule):
    f = os.path.join("fixtures/bad", d, "expected")
    if os.path.isfile(f):
        return ", ".join(l.strip() for l in open(f) if l.strip())
    return f"{rule}:{sev[rule].capitalize()}"

row(f"{prefix}-ok", f"{prefix} · OK", f"Compliant example for the {title} ruleset. Expect 0 findings.", "fixtures/good")
for rule in sorted(sev):
    variants = [b for b in bad if b.split(".")[0] == rule]
    # The representative fixture is named after the rule, so the default set is a subset of "all".
    rep = rule if rule in variants else variants[0]
    for d in variants if mode == "all" else [rep]:
        asset = f"{prefix}-{rule}" if d == rep else f"{prefix}-{d.replace('.', '-')}"
        variant = f" Variant: {d}." if d != rule else ""
        row(asset, f"{prefix} · {rule} ({sev[rule]})",
            f"Example for the {title} ruleset that breaks `{rule}` ({sev[rule]}).{variant} Expect exactly: {expect(d, rule)}.",
            os.path.join("fixtures/bad", d))
if mode == "all" and os.path.isdir("fixtures/scope"):
    for d in sorted(os.listdir("fixtures/scope")):
        row(f"{prefix}-scope-{d}", f"{prefix} · scope {d}",
            f"Document the {title} ruleset must not flag. Expect 0 findings.", os.path.join("fixtures/scope", d))
PY
}

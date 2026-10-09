# A2A v1.0 Rulesets (Conformance + Safety) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two MuleSoft API Governance rulesets for A2A v1.0 Agent Cards: A2A Agent Card Conformance (22 rules) and A2A Agent Safety (12 rules). Each lives in its own public repo, every rule is proven by its own bad fixture, and nothing is submitted to P4A.

**Architecture:** Each repo is a root `ruleset.yaml` (AMF Validation Profile 1.0). Generated fixture projects (`scripts/fixtures.py`) are run through `scripts/check.sh`, which uses the pinned Anypoint CLI and governance plugin 1.1.4.
- **Card-level rules** target `api.Project` behind a classifier guard.
- **Per-element rules** target the element class directly (for example `core.skills`).
- Each rule is test-first: add its bad fixture, watch `check.sh` fail, add the rule, then watch it pass.

**Tech Stack:** AMF Validation Profile 1.0, `anypoint-cli-v4-public` 1.6.27 with `mulesoft-anypoint-cli-governance-plugin` 1.1.4, bash, Python 3 (stdlib only).

**Spec:** `docs/superpowers/specs/2026-10-09-a2a-v1-rulesets-design.md` (in this repo).

## Global Constraints

- Repos: `P4A-Policies-for-Agents/a2a-agent-card-conformance-ruleset` and `P4A-Policies-for-Agents/a2a-agent-safety-ruleset`, cloned under `ms-omni-governance-rulesets/`.
- Profile names and Exchange asset IDs:
  - `A2A Agent Card Conformance` / `a2a-agent-card-conformance`
  - `A2A Agent Safety` / `a2a-agent-safety`
  - Both start at version `1.0.0`.
- Target document: `agent-card.json` with `exchange.json` `"classifier": "a2a-v1-card"`, `"descriptorVersion": "1.0.0"`, `"main": "agent-card.json"`.
- Governance plugin **≥ 1.1.4** (only project-builder 2.7.0 parses `a2a-v1-card`). The global CLI (plugin 1.0.21) can't be used. `check.sh` reads `${ANYPOINT_CLI:-anypoint-cli-v4}`.
- Both profiles declare `prefixes: {api: http://anypoint.com/vocabs/api#, catalog: http://anypoint.com/vocabs/digital-repository#}`.
- Card-level rule ("G"):
  - `targetClass: api.Project`, `if: catalog.classifier in [a2a-v1-card]`.
  - Flat `then` paths under `api.contract / doc.encodes / …`.
  - Never use nested `propertyConstraints` under an `api.Project` path. It breaks every document with "Model validation is not supported for the API composite configuration".
- Per-element checks must target the element class, never a flat G path. Flat paths count values across all elements.
- Required strings use `minCount: 1` + `minLength: 1`. Required arrays use `minCount: 1`. Wherever a missing value matters, `in: [...]` needs `minCount: 1` next to it.
- Messages: one line that names the field, the problem and the fix. Plain YAML scalars must not contain `: ` or ` #`.
- **P4A hold.** No `submit_policy`, tier-2 `validate_ruleset`, `deploy_ruleset` or Exchange publish. We never publish to Exchange.
- Never cite `mulesoft-emu/*` repos in committed files.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push with `direnv exec . git push`.
- Never edit `fixtures/` by hand. Edit `scripts/fixtures.py` and run `python3 -I scripts/fixtures.py`.

## Review Focus

1. **Collided classes.** A v0.3 card or MCP manifest with insecure content (http URLs, an implicit flow, an API key in the query string) must produce 0 findings from either ruleset. Pinned by the adversarial `fixtures/scope/v03-card` and `fixtures/scope/mcp-manifest` (Tasks 1 and 9).
2. **Optional `provider` absent.** `provider-complete` must not fire. Pinned by `fixtures/scope/v1-no-provider` (Tasks 1 and 9).
3. **Only the second element is broken.** Per-element rules must still fire. Pinned by the `.second-interface` and `.second-skill` variants (Tasks 4, 5 and 9).
4. **snake_case aliases.** Aliases must not evade the rules silently. Pinned by the camelCase rule fixtures (Tasks 7, 11 and 12) and `oidc-url-https.snake-case`.
5. **Plugin too old.** An older plugin would mis-parse silently, so `check.sh` must fail fast. Pinned by the plugin-version RED step (Task 1, Step 5).

## Verified facts this plan relies on (spike, 2026-10-09, plugin 1.1.4)

- The full GOOD card below is schema-valid: no `example-validation-error`, `Conforms: true` against every probe.
- The scope fixtures (adversarial v0.3 card and MCP manifest) produce no legacy-mode output and 0 findings.
- `minLength` on a G path and `if: and:` both pass `validate-authoring` ("Ruleset is valid").
- `name: ""` fails `minCount 1 + minLength 1`, and `supportedInterfaces: []` fails `minCount: 1`.
- `core.oauth2SecurityScheme / core.oauth2MetadataUrl` and `core.openIdConnectSecurityScheme / core.openIdConnectUrl` with `pattern: ^https://` fire on http values.
- A rule with two failing paths reports **two** results with the same rule ID. `check.sh` dedupes them after the result-count guard.
- `validate-authoring` rejects per-element targetClasses with `[ERROR] Line N: Invalid targetClass: "core.X". …`. `governance:ruleset:validate` accepts them.

## File Structure

Each repo has the same layout:

```
ruleset.yaml            # the profile (P4A auto-discovers it at the root)
exchange.json           # assetId, name, description, main, version
scripts/fixtures.py     # GOOD + SCOPE (identical in both repos) + per-repo BAD/EXPECTED; writes fixtures/
scripts/check.sh        # test suite; per-repo config block at the top
fixtures/good/          # generated
fixtures/scope/{v03-card,mcp-manifest,v1-no-provider}/   # generated; must produce 0 findings
fixtures/bad/<rule-id>[.<variant>]/                       # generated; optional `expected` file
README.md
CHANGELOG.md
.envrc                  # export GH_TOKEN="$(gh auth token --user tbolis-at-mulesoft)"
```

The conformance repo also holds `docs/superpowers/{specs,plans}/`. Container files: `ms-omni-governance-rulesets/CLAUDE.md` (Task 13). Pinned CLI: `~/.cache/p4a-a2a-cli/` (Task 1, outside any repo).

Tasks 1–8 run in `a2a-agent-card-conformance-ruleset/`. Tasks 9–13 run in `a2a-agent-safety-ruleset/`. Every `scripts/check.sh` run uses:

```bash
export ANYPOINT_CLI=~/.cache/p4a-a2a-cli/node_modules/.bin/anypoint-cli-v4
```

---

## Conformance repo

### Task 1: Pinned CLI, harness, scope fixtures, `card-name-required`

**Files:**
- Create: `~/.cache/p4a-a2a-cli/package.json` (outside the repo)
- Create: `scripts/fixtures.py`, `scripts/check.sh`, `exchange.json`, `ruleset.yaml`, `.gitignore`

**Interfaces:**
- Produces:
  - `fixtures.py` helpers `iface(d, i=0)`, `skill(d, i=0)`, `scheme(d, name)`, `oauth_flows(d)`, `put(obj, key, value)`, `rename(obj, old, new)`.
  - The dicts `GOOD`, `SCOPE`, `BAD` and `EXPECTED` (name → list of `"<id>:<Severity>"`).
  - `check.sh` config vars `EXPECTED_AUTHORING_WARNINGS`, `AUTHORING_ALLOWED_CLASSES` and `SIBLING_GOOD`.
  - Later tasks only add `BAD`/`EXPECTED` entries and `ruleset.yaml` rules.

- [ ] **Step 1: Install the pinned CLI**

```bash
mkdir -p ~/.cache/p4a-a2a-cli
cat > ~/.cache/p4a-a2a-cli/package.json <<'EOF'
{"private": true, "dependencies": {"anypoint-cli-v4-public": "1.6.27"}, "overrides": {"mulesoft-anypoint-cli-governance-plugin": "1.1.4"}}
EOF
(cd ~/.cache/p4a-a2a-cli && npm install --no-audit --no-fund)
~/.cache/p4a-a2a-cli/node_modules/.bin/anypoint-cli-v4 plugins --core | grep governance-plugin
```

Expected: `mulesoft-anypoint-cli-governance-plugin 1.1.4 (core)`.

- [ ] **Step 2: Write `scripts/fixtures.py`**

```python
"""Generate fixtures/ from GOOD plus one mutation per bad fixture.

Run from the repo root:  python3 -I scripts/fixtures.py
This deletes and rewrites fixtures/. Never edit fixtures/ by hand.

Bad fixture names are <rule-id> or <rule-id>.<variant>. scripts/check.sh expects
each one to produce exactly one finding, for <rule-id>, unless EXPECTED lists the
full set of findings (written to the fixture's `expected` file).
"""
import copy
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent / "fixtures"

# --- Keep everything from here to "per-repo" identical in both A2A ruleset repos. ---

# A2A v1.0 card that passes BOTH A2A Agent Card Conformance and A2A Agent Safety.
GOOD = {
    "name": "Weather Agent",
    "description": "Answers questions about current weather and forecasts for a city.",
    "supportedInterfaces": [
        {"url": "https://weather.example.com/a2a/v1", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"},
        {"url": "https://weather.example.com/a2a/grpc", "protocolBinding": "GRPC", "protocolVersion": "1.0"},
    ],
    "provider": {"organization": "Example Corp", "url": "https://example.com"},
    "version": "1.0.0",
    "documentationUrl": "https://example.com/docs/weather-agent",
    "capabilities": {"streaming": True, "pushNotifications": False, "extendedAgentCard": True},
    "securitySchemes": {
        "bearer": {"httpAuthSecurityScheme": {"scheme": "Bearer", "bearerFormat": "JWT"}},
        "oauth": {
            "oauth2SecurityScheme": {
                "oauth2MetadataUrl": "https://auth.example.com/.well-known/oauth-authorization-server",
                "flows": {
                    "authorizationCode": {
                        "authorizationUrl": "https://auth.example.com/authorize",
                        "tokenUrl": "https://auth.example.com/token",
                        "scopes": {"weather:read": "Read weather data"},
                        "pkceRequired": True,
                    }
                },
            }
        },
        "oidc": {
            "openIdConnectSecurityScheme": {
                "openIdConnectUrl": "https://id.example.com/.well-known/openid-configuration"
            }
        },
        "key": {"apiKeySecurityScheme": {"location": "header", "name": "X-API-Key"}},
    },
    "securityRequirements": [
        {"schemes": {"bearer": {"list": []}}},
        {"schemes": {"oauth": {"list": ["weather:read"]}}},
    ],
    "defaultInputModes": ["text/plain"],
    "defaultOutputModes": ["text/plain", "application/json"],
    "skills": [
        {
            "id": "current-weather",
            "name": "Current weather",
            "description": "Reports the current weather for a city.",
            "tags": ["weather"],
            "examples": ["What's the weather in Paris?"],
        },
        {
            "id": "forecast",
            "name": "Forecast",
            "description": "Gives a five-day forecast for a city.",
            "tags": ["weather", "forecast"],
        },
    ],
    "signatures": [{"protected": "eyJhbGciOiJFUzI1NiJ9", "signature": "c2lnbmF0dXJl"}],
}

# v0.3 card (classifier a2a-card). Its required fields are complete, but its transport and auth
# are insecure, so a v1 rule leaking onto a colliding v0.3 class shows up as a finding.
V03_CARD = {
    "protocolVersion": "0.3.0",
    "name": "Weather Agent",
    "description": "Answers questions about current weather and forecasts for a city.",
    "url": "http://weather.example.com/a2a",
    "preferredTransport": "JSONRPC",
    "provider": {"organization": "Example Corp", "url": "https://example.com"},
    "version": "1.0.0",
    "capabilities": {"streaming": True, "pushNotifications": False},
    "securitySchemes": {
        "legacy": {
            "type": "oauth2",
            "flows": {"implicit": {"authorizationUrl": "http://auth.example.com/authorize", "scopes": {}}},
        },
        "key": {"type": "apiKey", "in": "query", "name": "api_key"},
    },
    "security": [{"legacy": []}],
    "defaultInputModes": ["text/plain"],
    "defaultOutputModes": ["text/plain"],
    "skills": [
        {"id": "current-weather", "name": "Current weather", "description": "Reports the current weather.", "tags": ["weather"]}
    ],
}

# MCP manifest (classifier mcp-metadata) that reuses the colliding classes core.encodes,
# core.provider, core.capabilities and core.flows, with insecure values.
MCP_MANIFEST = {
    "protocolVersion": "2025-06-18",
    "transport": {"kind": "streamableHttp", "path": "/mcp"},
    "provider": {"organization": "Example Corp", "url": "http://example.com"},
    "capabilities": {"tools": {}},
    "securitySchemes": {
        "legacy": {
            "type": "oauth2",
            "flows": {
                "implicit": {"authorizationUrl": "http://auth.example.com/authorize", "scopes": {}},
                "password": {"tokenUrl": "http://auth.example.com/token", "scopes": {}},
            },
        },
        "key": {"type": "apiKey", "in": "query", "name": "api_key"},
        "oidc": {"type": "openIdConnect", "openIdConnectUrl": "http://id.example.com/.well-known/openid-configuration"},
    },
    "tools": [
        {"name": "get_weather", "description": "Gets the current weather for a city.", "inputSchema": {"type": "object", "properties": {}}}
    ],
}

# Documents both rulesets must accept with 0 findings: name -> (main file, classifier, document).
SCOPE = {
    "v03-card": ("agent-card.json", "a2a-card", V03_CARD),
    "mcp-manifest": ("mcp-metadata.json", "mcp-metadata", MCP_MANIFEST),
    # provider is optional in v1.0; provider-complete must not fire when it is absent.
    "v1-no-provider": ("agent-card.json", "a2a-v1-card", {k: v for k, v in GOOD.items() if k != "provider"}),
}


def iface(d, i=0):
    return d["supportedInterfaces"][i]


def skill(d, i=0):
    return d["skills"][i]


def scheme(d, name):
    """The wrapped scheme object, e.g. scheme(d, "oauth") -> the oauth2SecurityScheme dict."""
    return next(iter(d["securitySchemes"][name].values()))


def oauth_flows(d):
    return scheme(d, "oauth")["flows"]


def put(obj, key, value):
    obj[key] = value


def rename(obj, old, new):
    obj[new] = obj.pop(old)


def write(name, doc, main_file="agent-card.json", classifier="a2a-v1-card", expected=None):
    path = ROOT / name
    path.mkdir(parents=True)
    (path / main_file).write_text(json.dumps(doc, indent=2) + "\n")
    asset = name.replace("/", "-").replace(".", "-")
    exchange = {
        "main": main_file,
        "name": asset,
        "groupId": "p4a-fixtures",
        "assetId": asset,
        "version": "1.0.0",
        "classifier": classifier,
        "descriptorVersion": "1.0.0",
    }
    (path / "exchange.json").write_text(json.dumps(exchange, indent=2) + "\n")
    if expected:
        (path / "expected").write_text("".join(f"{line}\n" for line in sorted(expected)))


# --- per-repo: bad fixtures for this ruleset ---

BAD = {
    "card-name-required": lambda d: d.pop("name"),
    "card-name-required.empty": lambda d: put(d, "name", ""),
}

# Fixtures that legitimately trip more than one rule: name -> every "<id>:<Severity>" expected.
EXPECTED = {}


def main():
    unknown = set(EXPECTED) - set(BAD)
    if unknown:
        raise SystemExit(f"EXPECTED names without a BAD entry: {sorted(unknown)}")
    shutil.rmtree(ROOT, ignore_errors=True)
    write("good", GOOD)
    for name, (main_file, classifier, doc) in SCOPE.items():
        write(f"scope/{name}", doc, main_file, classifier)
    for name, mutate in BAD.items():
        doc = copy.deepcopy(GOOD)
        mutate(doc)
        write(f"bad/{name}", doc, expected=EXPECTED.get(name))


if __name__ == "__main__":
    main()
```

Run: `python3 -I scripts/fixtures.py && ls fixtures fixtures/scope fixtures/bad`
Expected: `bad good scope` / `mcp-manifest v03-card v1-no-provider` / `card-name-required card-name-required.empty`.

- [ ] **Step 3: Write `scripts/check.sh`** (then run `chmod +x scripts/check.sh`)

```bash
#!/usr/bin/env bash
# Test suite for this ruleset. Run from anywhere: scripts/check.sh
# Needs governance plugin >= 1.1.4; set ANYPOINT_CLI to pick the CLI (README "Development").
# Prints PASS lines; exits 1 with a FAIL line on the first failed assertion.
set -euo pipefail
cd "$(dirname "$0")/.."

# --- per-repo config ---
EXPECTED_AUTHORING_WARNINGS=0
# validate-authoring has no A2A domain, so it rejects these per-element targetClasses (README "Limitations").
AUTHORING_ALLOWED_CLASSES="core.supportedInterfaces core.skills core.signatures"
SIBLING_GOOD=../a2a-agent-safety-ruleset/fixtures/good
# -----------------------

RULESET=ruleset.yaml
CLI=${ANYPOINT_CLI:-anypoint-cli-v4}
MIN_PLUGIN=1.1.4

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Rule IDs listed under a top-level severity key (violation|warning|info).
severity_ids() {
  awk -v key="$1:" '$0 == key { on = 1; next } /^[^ ]/ { on = 0 } on && /^  - / { print $2 }' "$RULESET"
}

# Rule IDs defined directly under `validations:`.
defined_ids() {
  awk '/^validations:/ { on = 1; next } /^[^ ]/ { on = 0 } on && /^  [a-z0-9-]+:$/ { sub(":", "", $1); print $1 }' "$RULESET"
}

# CLI severity label for a rule ID (Violation|Warning|Info); fails if unlisted.
expected_severity() {
  local sev
  for sev in violation warning info; do
    if severity_ids "$sev" | grep -qx "$1"; then
      case $sev in violation) echo Violation ;; warning) echo Warning ;; info) echo Info ;; esac
      return 0
    fi
  done
  return 1
}

# Sorted, unique "<rule-id>:<Severity>" lines for one fixture project.
# A rule with several failing paths reports one result per path; those collapse to one line.
findings() {
  local out
  out=$("$CLI" governance:api:validate "$1" --rulesets "$RULESET" --no-collectMetrics 2>&1) || true
  grep -q '^Conforms:' <<<"$out" || fail "$1: validator did not run:"$'\n'"$out"
  if grep -q 'example-validation-error' <<<"$out"; then
    fail "$1: document fails its JSON schema (example-validation-error):"$'\n'"$out"
  fi
  if grep -qE 'falling back to legacy mode|Legacy project descriptor' <<<"$out"; then
    fail "$1: validator ran in legacy mode (check exchange.json classifier):"$'\n'"$out"
  fi
  local parsed reported raw
  parsed=$(awk '/^Constraint: / { n = split($2, a, "/"); id = a[n] } /^Severity: / { print id ":" $2; id = "" }' <<<"$out" | sort)
  # Guard against output the awk does not understand: every result must be parsed.
  reported=$(sed -n 's/^Number of results: //p' <<<"$out")
  raw=$(grep -cE '^[[:space:]-]*Constraint:' <<<"$out" || true)
  [ "$(grep -c . <<<"$parsed" || true)" = "${reported:-0}" ] && [ "$raw" = "${reported:-0}" ] \
    || fail "$1: parsed findings do not match 'Number of results: ${reported:-0}':"$'\n'"$out"
  [ -z "$parsed" ] || uniq <<<"$parsed"
}

lint() {
  local listed dup
  [ "$(grep -m1 -v '^[[:space:]]*$' "$RULESET")" = '#%Validation Profile 1.0' ] \
    || fail "first non-blank line must be '#%Validation Profile 1.0'"
  grep -qE '^profile: .+' "$RULESET" || fail "missing non-empty 'profile:' name"
  grep -qx '  api: http://anypoint.com/vocabs/api#' "$RULESET" \
    || fail "missing prefix 'api: http://anypoint.com/vocabs/api#'"
  grep -qx '  catalog: http://anypoint.com/vocabs/digital-repository#' "$RULESET" \
    || fail "missing prefix 'catalog: http://anypoint.com/vocabs/digital-repository#'"
  listed=$({ severity_ids violation; severity_ids warning; severity_ids info; } | sort)
  [ -n "$listed" ] || fail "no rules listed under violation/warning/info"
  dup=$(uniq -d <<<"$listed")
  [ -z "$dup" ] || fail "rules listed more than once: $dup"
  [ "$listed" = "$(defined_ids | sort)" ] || fail "severity lists and validations: keys differ"
  [ "$(wc -c <"$RULESET")" -lt 524288 ] || fail "$RULESET is larger than 512 KB"
  pass "tier-1 lint"
}

command -v "$CLI" >/dev/null || fail "CLI not found: $CLI (set ANYPOINT_CLI; see README Development)"
plugin=$("$CLI" plugins --core | grep governance-plugin) || fail "$CLI has no governance plugin"
plugin_version=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$plugin" | head -n1)
printf '%s\n%s\n' "$MIN_PLUGIN" "$plugin_version" | sort -V -C \
  || fail "governance plugin $plugin_version is older than $MIN_PLUGIN and cannot parse a2a-v1-card (see README Development)"
echo "CLI: $("$CLI" --version) / $plugin"

lint

out=$("$CLI" governance:ruleset:validate-authoring "$RULESET" 2>&1) || true
# A clean ruleset prints "Ruleset is valid" instead of the error/warning summary.
if grep -qx 'Ruleset is valid' <<<"$out"; then
  errors=0 warnings=0
else
  summary=$(grep -E '^[0-9]+ error\(s\), [0-9]+ warning\(s\)' <<<"$out") || fail "validate-authoring did not run:"$'\n'"$out"
  read -r errors _ warnings _ <<<"$summary"
fi
error_lines=$(grep -E '^\[ERROR\]' <<<"$out" || true)
[ "$(grep -c . <<<"$error_lines" || true)" = "$errors" ] \
  || fail "validate-authoring: could not parse $errors error line(s):"$'\n'"$out"
allowed=$(sed 's/\./\\./g; s/ /|/g' <<<"$AUTHORING_ALLOWED_CLASSES")
unexpected=$(grep -vE "Invalid targetClass: \"($allowed)\"" <<<"$error_lines" || true)
[ -z "$unexpected" ] || fail "validate-authoring: unexpected error(s):"$'\n'"$unexpected"
[ "$warnings" = "$EXPECTED_AUTHORING_WARNINGS" ] \
  || fail "validate-authoring: $warnings warning(s), expected $EXPECTED_AUTHORING_WARNINGS"$'\n'"$out"
pass "validate-authoring ($errors allowlisted targetClass error(s), $warnings warning(s))"

out=$("$CLI" governance:ruleset:validate "$RULESET" --no-collectMetrics 2>&1) || true
grep -q 'Ruleset conforms with Dialect' <<<"$out" || fail "dialect validation:"$'\n'"$out"
pass "dialect validate"

got=$(findings fixtures/good)
[ -z "$got" ] || fail "fixtures/good should have 0 findings, got:"$'\n'"$got"
pass "fixtures/good: 0 findings"

if [ -d "$SIBLING_GOOD" ]; then
  got=$(findings "$SIBLING_GOOD")
  [ -z "$got" ] || fail "$SIBLING_GOOD should have 0 findings, got:"$'\n'"$got"
  pass "$SIBLING_GOOD: 0 findings"
fi

# Other documents (v0.3 cards, MCP manifests, optional-field variants) must produce nothing.
for dir in fixtures/scope/*/; do
  got=$(findings "$dir")
  [ -z "$got" ] || fail "${dir%/} should have 0 findings, got:"$'\n'"$got"
  pass "${dir%/}: 0 findings"
done

for id in $(defined_ids); do
  [ -d "fixtures/bad/$id" ] || compgen -G "fixtures/bad/$id.*" >/dev/null \
    || fail "rule $id has no fixtures/bad/$id[.<variant>] fixture"
done

for dir in fixtures/bad/*/; do
  name=$(basename "$dir")
  id=${name%%.*}
  sev=$(expected_severity "$id") || fail "fixtures/bad/$name: no rule named $id in $RULESET"
  want="$id:$sev"
  # An optional `expected` file (written by fixtures.py) lists every finding the fixture must produce.
  if [ -f "$dir/expected" ]; then
    want=$(sort -u "$dir/expected")
    grep -qx "$id:$sev" <<<"$want" || fail "fixtures/bad/$name/expected must include '$id:$sev'"
  fi
  got=$(findings "$dir")
  [ "$got" = "$want" ] || fail "fixtures/bad/$name: expected exactly:"$'\n'"$want"$'\n'"got:"$'\n'"${got:-<none>}"
  pass "fixtures/bad/$name -> ${want//$'\n'/ }"
done

echo "ALL CHECKS PASSED"
```

- [ ] **Step 4: Write `exchange.json`, `.gitignore` and a skeleton `ruleset.yaml` with no rules**

`exchange.json`:

```json
{
  "main": "ruleset.yaml",
  "name": "A2A Agent Card Conformance",
  "description": "Enforces the fields the A2A v1.0 specification marks REQUIRED in Agent Cards: card identity, interfaces, modes, skills, provider, signatures, and camelCase JSON.",
  "assetId": "a2a-agent-card-conformance",
  "version": "1.0.0"
}
```

`.gitignore`:

```
.superpowers/
```

`ruleset.yaml`:

```yaml
#%Validation Profile 1.0
profile: A2A Agent Card Conformance
description: >-
  Enforces the parts of an A2A v1.0 Agent Card that the A2A specification marks REQUIRED and
  that Anypoint's agent card schema does not enforce: card identity, interfaces, input and
  output modes, skills, provider, signatures, and camelCase JSON. Applies to Exchange assets
  with classifier a2a-v1-card. Pairs with A2A Agent Safety.
prefixes:
  api: http://anypoint.com/vocabs/api#
  catalog: http://anypoint.com/vocabs/digital-repository#
validations: {}
```

- [ ] **Step 5: RED. The old global CLI is rejected.**

Run: `ANYPOINT_CLI=anypoint-cli-v4 scripts/check.sh`
Expected: `FAIL: governance plugin 1.0.21 is older than 1.1.4 and cannot parse a2a-v1-card …`. If the global CLI is already ≥ 1.1.4, skip this step and ledger it.

- [ ] **Step 6: RED. The empty ruleset fails lint.**

Run: `scripts/check.sh` (with `ANYPOINT_CLI` exported as described above)
Expected: the `CLI: …/ mulesoft-anypoint-cli-governance-plugin 1.1.4 (core)` line, then `FAIL: no rules listed under violation/warning/info`.

- [ ] **Step 7: GREEN. Add `card-name-required`.**

In `ruleset.yaml`, replace `validations: {}` with:

```yaml
violation:
  - card-name-required
validations:
  card-name-required:
    message: Agent Card has no `name`, or it is empty. Set `name` to a human-readable agent name (A2A v1.0 marks AgentCard.name REQUIRED).
    documentation: |
      Clients and registries show `name` to people choosing an agent. A2A v1.0 marks
      AgentCard.name REQUIRED, but Anypoint's agent card schema does not enforce it, so a
      card without a name publishes cleanly. This finding is reported on the asset, not on a
      line of the card.
    examples:
      valid: |
        {"name": "Weather Agent", "description": "Answers weather questions.", "version": "1.0.0"}
      invalid: |
        {"description": "Answers weather questions.", "version": "1.0.0"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.name:
          minCount: 1
          minLength: 1
```

Run: `scripts/check.sh`
Expected:
- `PASS: tier-1 lint`
- `PASS: validate-authoring (0 allowlisted targetClass error(s), 0 warning(s))`
- `PASS: dialect validate`
- `PASS: fixtures/good: 0 findings`
- the three `PASS: fixtures/scope/…: 0 findings` lines
- `PASS: fixtures/bad/card-name-required -> card-name-required:Violation` and the same for `.empty`
- `ALL CHECKS PASSED`

The sibling repo has no `fixtures/good` yet, so its line is absent.

- [ ] **Step 8: Commit**

```bash
git add .gitignore exchange.json ruleset.yaml scripts fixtures
git commit -m "feat: harness, scope fixtures and card-name-required

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The remaining card-level required rules

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`), `ruleset.yaml`

**Interfaces:**
- Consumes: `put` and `BAD` from Task 1, and the G rule shape from Task 1, Step 7.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "card-description-required": lambda d: d.pop("description"),
    "card-description-required.empty": lambda d: put(d, "description", ""),
    "card-version-required": lambda d: d.pop("version"),
    "card-version-required.empty": lambda d: put(d, "version", ""),
    "card-capabilities-required": lambda d: d.pop("capabilities"),
    "card-supported-interfaces-required": lambda d: d.pop("supportedInterfaces"),
    "card-supported-interfaces-required.empty-array": lambda d: put(d, "supportedInterfaces", []),
    "card-default-input-modes-required": lambda d: d.pop("defaultInputModes"),
    "card-default-input-modes-required.empty-array": lambda d: put(d, "defaultInputModes", []),
    "card-default-output-modes-required": lambda d: d.pop("defaultOutputModes"),
    "card-default-output-modes-required.empty-array": lambda d: put(d, "defaultOutputModes", []),
    "card-skills-required": lambda d: d.pop("skills"),
    "card-skills-required.empty-array": lambda d: put(d, "skills", []),
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/card-capabilities-required: no rule named card-capabilities-required in ruleset.yaml` (the first missing rule, alphabetically).

- [ ] **Step 3: GREEN. Add the 7 rules.**

Add the IDs under `violation:` (keep the list alphabetical):

```yaml
  - card-capabilities-required
  - card-default-input-modes-required
  - card-default-output-modes-required
  - card-description-required
  - card-skills-required
  - card-supported-interfaces-required
  - card-version-required
```

Append under `validations:`:

```yaml
  card-description-required:
    message: Agent Card has no `description`, or it is empty. Describe what the agent does in one or two sentences (A2A v1.0 marks AgentCard.description REQUIRED).
    documentation: |
      Clients, registries and routing agents read `description` to decide whether this agent
      can handle a task. A2A v1.0 marks AgentCard.description REQUIRED. This finding is
      reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"name": "Weather Agent", "description": "Answers weather questions for a city."}
      invalid: |
        {"name": "Weather Agent", "description": ""}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.description:
          minCount: 1
          minLength: 1
  card-version-required:
    message: Agent Card has no `version`, or it is empty. Set `version` to the agent's own version, for example 1.0.0 (A2A v1.0 marks AgentCard.version REQUIRED).
    documentation: |
      `version` is the agent's version, not the protocol's. Clients and caches use it to tell
      card revisions apart. A2A v1.0 marks AgentCard.version REQUIRED. This finding is
      reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"name": "Weather Agent", "version": "1.0.0"}
      invalid: |
        {"name": "Weather Agent"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.version:
          minCount: 1
          minLength: 1
  card-capabilities-required:
    message: Agent Card has no `capabilities` object. Add `capabilities` and declare streaming, pushNotifications and extendedAgentCard as they apply (A2A v1.0 marks AgentCard.capabilities REQUIRED).
    documentation: |
      Clients read `capabilities` to know whether they may stream, register push
      notifications, or fetch an extended card. Without it they must guess. A2A v1.0 marks
      AgentCard.capabilities REQUIRED. This finding is reported on the asset, not on a line of
      the card.
    examples:
      valid: |
        {"capabilities": {"streaming": true, "pushNotifications": false}}
      invalid: |
        {"name": "Weather Agent"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.capabilities:
          minCount: 1
  card-supported-interfaces-required:
    message: Agent Card has no `supportedInterfaces`, or the list is empty. Declare at least one AgentInterface with url, protocolBinding and protocolVersion (A2A v1.0 marks AgentCard.supportedInterfaces REQUIRED).
    documentation: |
      `supportedInterfaces` is the only place a v1.0 card says where and how to reach the
      agent. A card without it can't be called. A2A v1.0 marks it REQUIRED, and required
      arrays must hold at least one element. This finding is reported on the asset, not on a
      line of the card.
    examples:
      valid: |
        {"supportedInterfaces": [{"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}]}
      invalid: |
        {"supportedInterfaces": []}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.supportedInterfaces:
          minCount: 1
  card-default-input-modes-required:
    message: Agent Card has no `defaultInputModes`, or the list is empty. List the media types the agent accepts, for example text/plain (A2A v1.0 marks AgentCard.defaultInputModes REQUIRED).
    documentation: |
      Clients use `defaultInputModes` to decide which message parts they may send. A2A v1.0
      marks it REQUIRED, and required arrays must hold at least one element. This finding is
      reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"defaultInputModes": ["text/plain"]}
      invalid: |
        {"defaultInputModes": []}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.defaultInputModes:
          minCount: 1
  card-default-output-modes-required:
    message: Agent Card has no `defaultOutputModes`, or the list is empty. List the media types the agent returns, for example text/plain (A2A v1.0 marks AgentCard.defaultOutputModes REQUIRED).
    documentation: |
      Clients use `defaultOutputModes` to know which response parts they must handle. A2A
      v1.0 marks it REQUIRED, and required arrays must hold at least one element. This finding
      is reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"defaultOutputModes": ["text/plain", "application/json"]}
      invalid: |
        {"name": "Weather Agent"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.defaultOutputModes:
          minCount: 1
  card-skills-required:
    message: Agent Card has no `skills`, or the list is empty. Declare at least one AgentSkill (A2A v1.0 marks AgentCard.skills REQUIRED).
    documentation: |
      Skills are how routing agents and registries match tasks to agents. A card with no
      skills can't be discovered for any task. A2A v1.0 marks AgentCard.skills REQUIRED, and
      required arrays must hold at least one element. This finding is reported on the asset,
      not on a line of the card.
    examples:
      valid: |
        {"skills": [{"id": "current-weather", "name": "Current weather", "description": "Reports the weather.", "tags": ["weather"]}]}
      invalid: |
        {"skills": []}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.skills:
          minCount: 1
```

Run: `scripts/check.sh`
Expected: a `PASS: fixtures/bad/<name> -> <id>:Violation` line for each of the 15 bad fixtures, then `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: card-level required-field rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `provider-complete`

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`), `ruleset.yaml`

**Interfaces:**
- Consumes: `put` and `BAD`, and `fixtures/scope/v1-no-provider` from Task 1 (Review Focus 2).

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "provider-complete.no-organization": lambda d: d["provider"].pop("organization"),
    "provider-complete.no-url": lambda d: d["provider"].pop("url"),
    "provider-complete.empty-url": lambda d: put(d["provider"], "url", ""),
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/provider-complete.empty-url: no rule named provider-complete in ruleset.yaml`.

- [ ] **Step 3: GREEN.** Add `  - provider-complete` under `violation:`, and append:

```yaml
  provider-complete:
    message: Agent Card `provider` is missing `organization` or `url`, or one is empty. Set both, or remove `provider` (A2A v1.0 marks AgentProvider.organization and AgentProvider.url REQUIRED).
    documentation: |
      `provider` is optional, but when a card declares it, A2A v1.0 requires both
      `organization` and `url`. Registries show them so people can see who operates the agent
      and how to reach them. This finding is reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"provider": {"organization": "Example Corp", "url": "https://example.com"}}
      invalid: |
        {"provider": {"organization": "Example Corp"}}
    targetClass: api.Project
    if:
      and:
        - propertyConstraints:
            catalog.classifier:
              in: [a2a-v1-card]
        - propertyConstraints:
            api.contract / doc.encodes / core.provider:
              minCount: 1
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.provider / core.organization:
          minCount: 1
          minLength: 1
        api.contract / doc.encodes / core.provider / core.url:
          minCount: 1
          minLength: 1
```

Run: `scripts/check.sh`
Expected: `PASS: fixtures/scope/v1-no-provider: 0 findings`, three `-> provider-complete:Violation` lines, then `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: provider-complete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Interface rules (5)

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`, `EXPECTED`), `ruleset.yaml`

**Interfaces:**
- Consumes: `iface`, `put`, `BAD` and `EXPECTED`. `AUTHORING_ALLOWED_CLASSES` already contains `core.supportedInterfaces`.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "interface-url-required": lambda d: iface(d).pop("url"),
    # Review Focus 3: only the second interface is broken.
    "interface-url-required.second-interface": lambda d: iface(d, 1).pop("url"),
    "interface-url-required.empty": lambda d: put(iface(d), "url", ""),
    "interface-protocol-binding-required": lambda d: iface(d).pop("protocolBinding"),
    "interface-protocol-binding-required.empty": lambda d: put(iface(d), "protocolBinding", ""),
    "interface-protocol-version-required": lambda d: iface(d).pop("protocolVersion"),
    "interface-protocol-version-required.empty": lambda d: put(iface(d), "protocolVersion", ""),
    "interface-protocol-version-format": lambda d: put(iface(d), "protocolVersion", "1.0.0"),
    "interface-protocol-version-format.second-interface": lambda d: put(iface(d, 1), "protocolVersion", "v1"),
    "interface-protocol-binding-known": lambda d: put(iface(d), "protocolBinding", "SOAP"),
```

Add to `EXPECTED`. An empty value also fails the format/known warning:

```python
    "interface-protocol-binding-required.empty": [
        "interface-protocol-binding-required:Violation",
        "interface-protocol-binding-known:Warning",
    ],
    "interface-protocol-version-required.empty": [
        "interface-protocol-version-required:Violation",
        "interface-protocol-version-format:Warning",
    ],
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/interface-protocol-binding-known: no rule named interface-protocol-binding-known in ruleset.yaml`.

- [ ] **Step 3: GREEN.**

Add under `violation:`:

```yaml
  - interface-protocol-binding-required
  - interface-protocol-version-required
  - interface-url-required
```

Add a new top-level `warning:` list, placed after the `violation:` list and before `validations:`:

```yaml
warning:
  - interface-protocol-binding-known
  - interface-protocol-version-format
```

Append under `validations:`:

```yaml
  interface-url-required:
    message: This supportedInterfaces entry has no `url`, or it is empty. Set the absolute URL where the interface is served.
    documentation: |
      AgentInterface.url is where clients send requests for this binding. A2A v1.0 marks it
      REQUIRED, and an interface without one is unreachable.
    examples:
      valid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
      invalid: |
        {"protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.url:
        minCount: 1
        minLength: 1
  interface-protocol-binding-required:
    message: This supportedInterfaces entry has no `protocolBinding`, or it is empty. Set JSONRPC, GRPC, HTTP+JSON or your custom binding.
    documentation: |
      AgentInterface.protocolBinding tells clients which wire format to speak at `url`. A2A
      v1.0 marks it REQUIRED.
    examples:
      valid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
      invalid: |
        {"url": "https://agent.example.com/a2a", "protocolVersion": "1.0"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.protocolBinding:
        minCount: 1
        minLength: 1
  interface-protocol-version-required:
    message: This supportedInterfaces entry has no `protocolVersion`, or it is empty. Set the A2A version the interface speaks, for example 1.0 (an empty value means 0.3).
    documentation: |
      AgentInterface.protocolVersion tells clients which A2A version the interface implements.
      A2A v1.0 marks it REQUIRED, and clients treat an empty value as 0.3. A v1.0 card that
      leaves it empty is therefore read as a 0.3 interface.
    examples:
      valid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
      invalid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": ""}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.protocolVersion:
        minCount: 1
        minLength: 1
  interface-protocol-version-format:
    message: This supportedInterfaces entry's `protocolVersion` is not Major.Minor. Use a value like 1.0, without a patch number.
    documentation: |
      A2A v1.0 versions the protocol as Major.Minor and says patch versions SHOULD NOT appear in
      protocolVersion. Clients negotiating versions may not match "1.0.0" or "v1" against "1.0".
    examples:
      valid: |
        {"protocolVersion": "1.0"}
      invalid: |
        {"protocolVersion": "1.0.0"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.protocolVersion:
        pattern: "^[0-9]+\\.[0-9]+$"
  interface-protocol-binding-known:
    message: This supportedInterfaces entry uses a `protocolBinding` other than JSONRPC, GRPC or HTTP+JSON. Use a core binding unless every client is known to support the custom one.
    documentation: |
      A2A v1.0 defines three core bindings (JSONRPC, GRPC, HTTP+JSON) and allows custom ones.
      Generic A2A clients only speak the core bindings, so a custom-only card is unreachable to
      them. This is a warning because custom bindings are legal.
    examples:
      valid: |
        {"protocolBinding": "HTTP+JSON"}
      invalid: |
        {"protocolBinding": "SOAP"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.protocolBinding:
        in: [JSONRPC, GRPC, "HTTP+JSON"]
```

Run: `scripts/check.sh`
Expected:
- `PASS: validate-authoring (N allowlisted targetClass error(s), 0 warning(s))` with N ≥ 1.
- All 10 new fixtures pass. The two `.empty` variants list both IDs.
- `ALL CHECKS PASSED`.

If the plugin flags the `pattern` escaping, keep the JSON-style `"^[0-9]+\\.[0-9]+$"`: it was verified in the spike.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: supportedInterfaces rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Skill rules (4)

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`), `ruleset.yaml`

**Interfaces:**
- Consumes: `skill`, `put` and `BAD`. `fixtures/scope/v03-card` (its v0.3 skills are complete) proves these rules accept compliant v0.3 skills.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "skill-id-required": lambda d: skill(d).pop("id"),
    # Review Focus 3: only the second skill is broken.
    "skill-id-required.second-skill": lambda d: skill(d, 1).pop("id"),
    "skill-name-required": lambda d: skill(d).pop("name"),
    "skill-name-required.empty": lambda d: put(skill(d), "name", ""),
    "skill-description-required": lambda d: skill(d).pop("description"),
    "skill-description-required.second-skill": lambda d: skill(d, 1).pop("description"),
    "skill-description-required.empty": lambda d: put(skill(d), "description", ""),
    "skill-tags-required": lambda d: skill(d).pop("tags"),
    "skill-tags-required.empty-array": lambda d: put(skill(d), "tags", []),
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/skill-description-required: no rule named skill-description-required in ruleset.yaml`.

- [ ] **Step 3: GREEN.**

Add under `violation:`:

```yaml
  - skill-description-required
  - skill-id-required
  - skill-name-required
  - skill-tags-required
```

Append under `validations:`:

```yaml
  skill-id-required:
    message: This skill has no `id`, or it is empty. Set a unique identifier, for example current-weather.
    documentation: |
      AgentSkill.id identifies the skill to clients and registries. A2A v1.0 marks it REQUIRED.
      This rule also runs on v0.3 cards, which have the same requirement.
    examples:
      valid: |
        {"id": "current-weather", "name": "Current weather", "description": "Reports the weather.", "tags": ["weather"]}
      invalid: |
        {"name": "Current weather", "description": "Reports the weather.", "tags": ["weather"]}
    targetClass: core.skills
    propertyConstraints:
      core.id:
        minCount: 1
        minLength: 1
  skill-name-required:
    message: This skill has no `name`, or it is empty. Set a human-readable skill name.
    documentation: |
      AgentSkill.name is what people see when browsing an agent's skills. A2A v1.0 marks it
      REQUIRED. This rule also runs on v0.3 cards, which have the same requirement.
    examples:
      valid: |
        {"id": "current-weather", "name": "Current weather"}
      invalid: |
        {"id": "current-weather", "name": ""}
    targetClass: core.skills
    propertyConstraints:
      core.name:
        minCount: 1
        minLength: 1
  skill-description-required:
    message: This skill has no `description`, or it is empty. Describe what the skill does so clients can route requests to it.
    documentation: |
      Routing agents pick a skill by reading its description. A2A v1.0 marks
      AgentSkill.description REQUIRED. This rule also runs on v0.3 cards, which have the same
      requirement.
    examples:
      valid: |
        {"id": "forecast", "description": "Gives a five-day forecast for a city."}
      invalid: |
        {"id": "forecast"}
    targetClass: core.skills
    propertyConstraints:
      core.description:
        minCount: 1
        minLength: 1
  skill-tags-required:
    message: This skill has no `tags`, or the list is empty. Add at least one keyword describing the skill.
    documentation: |
      Registries and routing agents filter skills by tag. A2A v1.0 marks AgentSkill.tags
      REQUIRED, and required arrays must hold at least one element. This rule also runs on v0.3
      cards, which have the same requirement.
    examples:
      valid: |
        {"id": "forecast", "tags": ["weather", "forecast"]}
      invalid: |
        {"id": "forecast", "tags": []}
    targetClass: core.skills
    propertyConstraints:
      core.tags:
        minCount: 1
```

Run: `scripts/check.sh`
Expected: `PASS: fixtures/scope/v03-card: 0 findings`, all 9 new fixtures pass, then `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: skill rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `signature-complete`

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`), `ruleset.yaml`

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "signature-complete.no-protected": lambda d: d["signatures"][0].pop("protected"),
    "signature-complete.no-signature": lambda d: d["signatures"][0].pop("signature"),
    "signature-complete.empty-signature": lambda d: put(d["signatures"][0], "signature", ""),
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/signature-complete.empty-signature: no rule named signature-complete in ruleset.yaml`.

- [ ] **Step 3: GREEN.** Add `  - signature-complete` under `violation:`, and append:

```yaml
  signature-complete:
    message: This Agent Card signature is missing `protected` or `signature`, or one is empty. Each AgentCardSignature needs the base64url protected header and the base64url signature.
    documentation: |
      A2A v1.0 cards may carry JWS signatures. AgentCardSignature.protected and
      AgentCardSignature.signature are REQUIRED. Without either, clients can't verify the card
      and must treat it as unsigned. This rule checks shape only. Verifying the signature is a
      runtime concern.
    examples:
      valid: |
        {"signatures": [{"protected": "eyJhbGciOiJFUzI1NiJ9", "signature": "c2lnbmF0dXJl"}]}
      invalid: |
        {"signatures": [{"protected": "eyJhbGciOiJFUzI1NiJ9"}]}
    targetClass: core.signatures
    propertyConstraints:
      core.protected:
        minCount: 1
        minLength: 1
      core.signature:
        minCount: 1
        minLength: 1
```

Run: `scripts/check.sh`
Expected: three `-> signature-complete:Violation` lines, then `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: signature-complete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: camelCase rules (3)

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`, `EXPECTED`), `ruleset.yaml`

**Interfaces:**
- Consumes: `rename`, `put`, `iface`, `skill` and `EXPECTED`.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "card-json-camel-case": lambda d: put(d, "icon_url", "https://example.com/icon.png"),
    "card-json-camel-case.supported-interfaces": lambda d: rename(d, "supportedInterfaces", "supported_interfaces"),
    "interface-json-camel-case": lambda d: rename(iface(d), "protocolVersion", "protocol_version"),
    "skill-json-camel-case": lambda d: put(skill(d), "input_modes", ["text/plain"]),
```

Add to `EXPECTED`. Each renamed field also counts as missing:

```python
    "card-json-camel-case.supported-interfaces": [
        "card-json-camel-case:Violation",
        "card-supported-interfaces-required:Violation",
    ],
    "interface-json-camel-case": [
        "interface-json-camel-case:Violation",
        "interface-protocol-version-required:Violation",
    ],
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/card-json-camel-case: no rule named card-json-camel-case in ruleset.yaml`.

- [ ] **Step 3: GREEN.**

Add under `violation:`:

```yaml
  - card-json-camel-case
  - interface-json-camel-case
  - skill-json-camel-case
```

Append under `validations:`:

```yaml
  card-json-camel-case:
    message: Agent Card uses a snake_case field name (supported_interfaces, default_input_modes, default_output_modes, documentation_url, icon_url, security_schemes or security_requirements). Rename it to camelCase; A2A v1.0 JSON MUST use camelCase.
    documentation: |
      A2A v1.0 says the JSON form of the card MUST use camelCase field names. Anypoint's card
      schema also accepts proto-style snake_case aliases and does not normalize them. A
      snake_case card therefore looks complete to its author while clients and every other
      rule see the field as missing. This finding is reported on the asset, not on a line of
      the card.
    examples:
      valid: |
        {"supportedInterfaces": [{"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}]}
      invalid: |
        {"supported_interfaces": [{"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}]}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.supported_interfaces:
          maxCount: 0
        api.contract / doc.encodes / core.default_input_modes:
          maxCount: 0
        api.contract / doc.encodes / core.default_output_modes:
          maxCount: 0
        api.contract / doc.encodes / core.documentation_url:
          maxCount: 0
        api.contract / doc.encodes / core.icon_url:
          maxCount: 0
        api.contract / doc.encodes / core.security_schemes:
          maxCount: 0
        api.contract / doc.encodes / core.security_requirements:
          maxCount: 0
  interface-json-camel-case:
    message: This supportedInterfaces entry uses protocol_binding or protocol_version. Rename it to protocolBinding or protocolVersion; A2A v1.0 JSON MUST use camelCase.
    documentation: |
      A2A v1.0 JSON MUST use camelCase. The snake_case aliases are accepted by Anypoint's
      schema but stored under a different name, so clients don't see the binding or version.
    examples:
      valid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
      invalid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocol_version": "1.0"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.protocol_binding:
        maxCount: 0
      core.protocol_version:
        maxCount: 0
  skill-json-camel-case:
    message: This skill uses input_modes, output_modes or security_requirements. Rename it to inputModes, outputModes or securityRequirements; A2A v1.0 JSON MUST use camelCase.
    documentation: |
      A2A v1.0 JSON MUST use camelCase. The snake_case aliases are accepted by Anypoint's
      schema but stored under a different name, so clients ignore the skill's modes and
      security requirements.
    examples:
      valid: |
        {"id": "forecast", "inputModes": ["text/plain"]}
      invalid: |
        {"id": "forecast", "input_modes": ["text/plain"]}
    targetClass: core.skills
    propertyConstraints:
      core.input_modes:
        maxCount: 0
      core.output_modes:
        maxCount: 0
      core.security_requirements:
        maxCount: 0
```

Run: `scripts/check.sh`
Expected: all 4 new fixtures pass, then `ALL CHECKS PASSED`. The conformance ruleset now has 22 rules: `defined_ids | wc -l` = 22.

**Ruling allowed.** If `validate-authoring` raises a warning on a snake_case property path (for example "unknown property"), record the exact text in the README "Known authoring warning" section, set `EXPECTED_AUTHORING_WARNINGS` to the observed count, and ledger it.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: camelCase JSON rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Conformance README, CHANGELOG, push

**Files:**
- Create: `README.md`, `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-10-09-a2a-v1-rulesets-design.md` (status line)

- [ ] **Step 1: Write `README.md`**

````markdown
# A2A Agent Card Conformance ruleset

A MuleSoft API Governance ruleset (AMF Validation Profile 1.0) for **A2A v1.0 Agent Cards**:
Exchange assets with classifier `a2a-v1-card`. It enforces the fields the A2A v1.0 specification
marks REQUIRED. Anypoint's agent card schema accepts cards that leave them out.

**Pairs with:**
- [A2A Agent Safety](https://github.com/P4A-Policies-for-Agents/a2a-agent-safety-ruleset), for
  transport security, authentication and signing.
- MuleSoft's *Agent Network Best Practices*, for Agent Network specs. Its card rules target
  v0.3 cards inside Agent Network specs, so they don't overlap with this ruleset.

## Rules

| Rule | Severity | Why | Fix |
|---|---|---|---|
| `card-name-required` | violation | AgentCard.name is REQUIRED | Set a non-empty `name` |
| `card-description-required` | violation | AgentCard.description is REQUIRED | Set a non-empty `description` |
| `card-version-required` | violation | AgentCard.version is REQUIRED | Set a non-empty `version` |
| `card-capabilities-required` | violation | AgentCard.capabilities is REQUIRED | Add `capabilities` |
| `card-supported-interfaces-required` | violation | Without interfaces the agent is unreachable | Add at least one `supportedInterfaces` entry |
| `card-default-input-modes-required` | violation | AgentCard.defaultInputModes is REQUIRED | List at least one media type |
| `card-default-output-modes-required` | violation | AgentCard.defaultOutputModes is REQUIRED | List at least one media type |
| `card-skills-required` | violation | AgentCard.skills is REQUIRED | Declare at least one skill |
| `provider-complete` | violation | AgentProvider.organization and .url are REQUIRED | Set both, or remove `provider` |
| `interface-url-required` | violation | AgentInterface.url is REQUIRED | Set the interface URL |
| `interface-protocol-binding-required` | violation | AgentInterface.protocolBinding is REQUIRED | Set the binding |
| `interface-protocol-version-required` | violation | Empty means 0.3 | Set e.g. `1.0` |
| `interface-protocol-version-format` | warning | Patch versions SHOULD NOT be used | Use Major.Minor |
| `interface-protocol-binding-known` | warning | Generic clients speak only core bindings | Use JSONRPC, GRPC or HTTP+JSON |
| `skill-id-required` | violation | AgentSkill.id is REQUIRED | Set `id` |
| `skill-name-required` | violation | AgentSkill.name is REQUIRED | Set `name` |
| `skill-description-required` | violation | AgentSkill.description is REQUIRED | Set `description` |
| `skill-tags-required` | violation | AgentSkill.tags is REQUIRED | Add at least one tag |
| `signature-complete` | violation | `protected` and `signature` are REQUIRED | Set both on every signature |
| `card-json-camel-case` | violation | JSON MUST be camelCase; aliases hide fields | Rename snake_case card fields |
| `interface-json-camel-case` | violation | Same, for interfaces | Rename `protocol_binding`/`protocol_version` |
| `skill-json-camel-case` | violation | Same, for skills | Rename `input_modes`/`output_modes`/`security_requirements` |

The `skill-*` and `signature-complete` rules also run on v0.3 cards, which have the same
requirements. A compliant v0.3 card produces no findings.

## Deploy it to your org

Find this ruleset in the [P4A catalog](https://www.p4a.ai) and deploy it to your Anypoint org,
either with **Publish to Exchange** or with the P4A MCP server's `deploy_ruleset`. Then apply it
through a governance profile that covers your A2A agent card assets.

## Limitations

- **Hosted support is unverified.** Validating `a2a-v1-card` assets needs governance plugin
  1.1.4 or later. It isn't yet confirmed that Anypoint's hosted governance validates these
  assets.
- **Card-level findings have no source location.** The `card-*` and `provider-complete` rules
  are reported on the asset, so their messages name the field.
- **`validate-authoring` false errors.** It has no A2A domain, so it reports `Invalid
  targetClass` for `core.supportedInterfaces`, `core.skills` and `core.signatures`.
  `governance:ruleset:validate` accepts the ruleset, and the fixtures prove each rule.
- **v0.3 cards are out of scope.** Only `skill-*` and `signature-complete` reach them.

## Development

`scripts/check.sh` needs governance plugin **1.1.4 or later**. One way to install it without
touching your global CLI:

```bash
mkdir -p ~/.cache/p4a-a2a-cli && cd ~/.cache/p4a-a2a-cli
echo '{"private":true,"dependencies":{"anypoint-cli-v4-public":"1.6.27"},"overrides":{"mulesoft-anypoint-cli-governance-plugin":"1.1.4"}}' > package.json
npm install --no-audit --no-fund
```

Then, from the repo root:

```bash
python3 -I scripts/fixtures.py
ANYPOINT_CLI=~/.cache/p4a-a2a-cli/node_modules/.bin/anypoint-cli-v4 scripts/check.sh
```

- `scripts/fixtures.py` generates every fixture: a compliant card, scope documents that must
  stay clean (a v0.3 card, an MCP manifest, a v1 card without `provider`), and one bad card per
  rule. Never edit `fixtures/` by hand.
- Bump `version` in `exchange.json` for every rule change.

## Source Ref

A2A Protocol Specification 1.0.0, https://a2a-protocol.org/latest/specification/ (snapshot
2026-10-09).
````

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## 1.0.0 (2026-10-09)

- Initial release: 22 rules for A2A v1.0 Agent Card conformance (20 violations, 2 warnings).
```

- [ ] **Step 3: Update the spec status.** In `docs/superpowers/specs/2026-10-09-a2a-v1-rulesets-design.md`:
  - replace `Status: draft, awaiting review.` with `Status: approved 2026-10-09.`
  - delete the sentence "Until the repos exist, the spec lives in the container folder at `ms-omni-governance-rulesets/docs/superpowers/specs/`." and the path line that follows it.

- [ ] **Step 4: Verify**

Run: `scripts/check.sh 2>&1 | tail -1 && rg -n 'mulesoft-emu|/Users/' README.md ruleset.yaml scripts docs || echo clean`
Expected: `ALL CHECKS PASSED`, then `clean`.

- [ ] **Step 5: Commit and push**

```bash
git add README.md CHANGELOG.md docs
git commit -m "docs: README, CHANGELOG, spec status

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
direnv exec . git push
```

Expected: the push to `main` succeeds. Do **not** tag yet; tagging `v1.0.0` waits for the user's go.

---

## Safety repo

### Task 9: Harness copy and `interface-url-https`

**Files:**
- Create: `scripts/fixtures.py`, `scripts/check.sh` (copied from the conformance repo), `exchange.json`, `ruleset.yaml`, `.gitignore`
- Commit: the existing `.envrc`

**Interfaces:**
- Consumes: the conformance repo's `scripts/fixtures.py` and `scripts/check.sh` as of Task 8.
- The `GOOD`/`SCOPE` section must stay byte-identical between the repos (check in Task 13).

- [ ] **Step 1: Copy and adapt the harness**

```bash
mkdir -p scripts
cp ../a2a-agent-card-conformance-ruleset/scripts/{fixtures.py,check.sh} scripts/
cp ../a2a-agent-card-conformance-ruleset/.gitignore .
```

In `scripts/check.sh`, replace the config block with:

```bash
EXPECTED_AUTHORING_WARNINGS=0
# validate-authoring has no A2A domain, so it rejects these per-element targetClasses (README "Limitations").
AUTHORING_ALLOWED_CLASSES="core.supportedInterfaces core.oauth2SecurityScheme core.apiKeySecurityScheme core.openIdConnectSecurityScheme"
SIBLING_GOOD=../a2a-agent-card-conformance-ruleset/fixtures/good
```

In `scripts/fixtures.py`, replace everything from `BAD = {` through the end of `EXPECTED = {…}` with:

```python
BAD = {
    "interface-url-https": lambda d: put(iface(d), "url", "http://weather.example.com/a2a/v1"),
    # Review Focus 3: only the second interface is plain HTTP.
    "interface-url-https.second-interface": lambda d: put(iface(d, 1), "url", "http://weather.example.com/a2a/grpc"),
}

# Fixtures that legitimately trip more than one rule: name -> every "<id>:<Severity>" expected.
EXPECTED = {}
```

`exchange.json`:

```json
{
  "main": "ruleset.yaml",
  "name": "A2A Agent Safety",
  "description": "Safety checks for A2A v1.0 Agent Cards: HTTPS interfaces and auth endpoints, authenticated extended cards, no deprecated OAuth flows, PKCE, API keys out of query strings, signed cards, and camelCase JSON.",
  "assetId": "a2a-agent-safety",
  "version": "1.0.0"
}
```

`ruleset.yaml` skeleton:

```yaml
#%Validation Profile 1.0
profile: A2A Agent Safety
description: >-
  Safety checks for A2A v1.0 Agent Cards (Exchange classifier a2a-v1-card): interfaces and
  auth endpoints use HTTPS, an extended card is protected by declared authentication, OAuth
  avoids deprecated flows and requires PKCE, API keys stay out of query strings, and the card
  is signed. Pairs with A2A Agent Card Conformance.
prefixes:
  api: http://anypoint.com/vocabs/api#
  catalog: http://anypoint.com/vocabs/digital-repository#
validations: {}
```

- [ ] **Step 2: RED**

Run: `chmod +x scripts/check.sh && python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: no rules listed under violation/warning/info`.

- [ ] **Step 3: GREEN.** Replace `validations: {}` with:

```yaml
violation:
  - interface-url-https
validations:
  interface-url-https:
    message: This supportedInterfaces entry's `url` does not start with https://. Serve the interface over TLS and publish its https URL (A2A v1.0 requires encrypted transport in production).
    documentation: |
      A2A v1.0 says production deployments MUST use encrypted transport. A plain-HTTP interface
      exposes tasks, messages and bearer tokens to anyone on the path. This rule also flags
      local development cards, which is intended for governed Exchange assets.
    examples:
      valid: |
        {"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
      invalid: |
        {"url": "http://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}
    targetClass: core.supportedInterfaces
    propertyConstraints:
      core.url:
        pattern: "^https://"
```

Run: `scripts/check.sh`
Expected:
- `PASS: fixtures/good: 0 findings`.
- `PASS: ../a2a-agent-card-conformance-ruleset/fixtures/good: 0 findings`.
- All three scope fixtures show 0 findings. The v0.3 card's `http://` url must not fire (Review Focus 1).
- Both bad fixtures pass.
- `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add .envrc .gitignore exchange.json ruleset.yaml scripts fixtures
git commit -m "feat: harness, scope fixtures and interface-url-https

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `extended-card-requires-auth` and `card-security-declared`

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`, `EXPECTED`), `ruleset.yaml`

**Interfaces:**
- Consumes: `put` and `EXPECTED`.
- GOOD has `capabilities.extendedAgentCard: true`, plus `securitySchemes` and `securityRequirements`.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "extended-card-requires-auth": lambda d: (d.pop("securitySchemes"), d.pop("securityRequirements")),
    "extended-card-requires-auth.no-requirements": lambda d: d.pop("securityRequirements"),
    # extendedAgentCard false or absent: only the card-level warning may fire.
    "card-security-declared": lambda d: (
        put(d["capabilities"], "extendedAgentCard", False),
        d.pop("securitySchemes"),
        d.pop("securityRequirements"),
    ),
    "card-security-declared.no-extended-flag": lambda d: (
        d["capabilities"].pop("extendedAgentCard"),
        d.pop("securitySchemes"),
        d.pop("securityRequirements"),
    ),
```

Add to `EXPECTED`:

```python
    "extended-card-requires-auth": [
        "extended-card-requires-auth:Violation",
        "card-security-declared:Warning",
    ],
    "extended-card-requires-auth.no-requirements": [
        "extended-card-requires-auth:Violation",
        "card-security-declared:Warning",
    ],
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/card-security-declared: no rule named card-security-declared in ruleset.yaml`.

- [ ] **Step 3: GREEN.**

Add `  - extended-card-requires-auth` under `violation:`, and add a `warning:` list:

```yaml
warning:
  - card-security-declared
```

Append under `validations:`:

```yaml
  extended-card-requires-auth:
    message: Agent Card sets capabilities.extendedAgentCard to true but declares no `securitySchemes` or no `securityRequirements`. Declare the scheme clients use to fetch the extended card (A2A v1.0 requires the extended card to be authenticated).
    documentation: |
      The extended Agent Card can expose skills and details hidden from the public card. A2A
      v1.0 says clients MUST authenticate to fetch it, using a scheme declared in the public
      card. A card that offers an extended card without declaring any scheme either leaks it
      or makes it unreachable. This finding is reported on the asset, not on a line of the
      card.
    examples:
      valid: |
        {"capabilities": {"extendedAgentCard": true},
         "securitySchemes": {"bearer": {"httpAuthSecurityScheme": {"scheme": "Bearer"}}},
         "securityRequirements": [{"schemes": {"bearer": {"list": []}}}]}
      invalid: |
        {"capabilities": {"extendedAgentCard": true}}
    targetClass: api.Project
    if:
      and:
        - propertyConstraints:
            catalog.classifier:
              in: [a2a-v1-card]
        - propertyConstraints:
            api.contract / doc.encodes / core.capabilities / core.extendedAgentCard:
              minCount: 1
              in: [true]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.securitySchemes:
          minCount: 1
        api.contract / doc.encodes / core.securityRequirements:
          minCount: 1
  card-security-declared:
    message: Agent Card declares no `securitySchemes` or no `securityRequirements`. Declare how clients authenticate so gateways can enforce it and clients can obtain credentials.
    documentation: |
      Clients and gateways read the card to learn how to authenticate. A card without declared
      security is either open to anyone or protected in a way clients can't discover. If the
      agent really is public, document that and accept this warning. This finding is reported
      on the asset, not on a line of the card.
    examples:
      valid: |
        {"securitySchemes": {"bearer": {"httpAuthSecurityScheme": {"scheme": "Bearer"}}},
         "securityRequirements": [{"schemes": {"bearer": {"list": []}}}]}
      invalid: |
        {"name": "Weather Agent"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.securitySchemes:
          minCount: 1
        api.contract / doc.encodes / core.securityRequirements:
          minCount: 1
```

Run: `scripts/check.sh`
Expected:
- `card-security-declared` and `.no-extended-flag` give only `card-security-declared:Warning`. This proves the extended rule ignores `false` and absent values.
- Both `extended-card-requires-auth` fixtures give both IDs.
- `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: extended-card-requires-auth and card-security-declared

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: OAuth rules (5)

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`), `ruleset.yaml`

**Interfaces:**
- Consumes: `scheme`, `oauth_flows`, `put` and `rename`.
- GOOD's `oauth` scheme has an https `oauth2MetadataUrl` and an `authorizationCode` flow with `pkceRequired: true`.

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    # Each replaces the flows object, so the authorizationCode PKCE rule has nothing to check.
    "oauth-no-implicit-flow": lambda d: put(scheme(d, "oauth"), "flows", {
        "implicit": {"authorizationUrl": "https://auth.example.com/authorize", "scopes": {"weather:read": "Read weather data"}}
    }),
    "oauth-no-password-flow": lambda d: put(scheme(d, "oauth"), "flows", {
        "password": {"tokenUrl": "https://auth.example.com/token", "scopes": {"weather:read": "Read weather data"}}
    }),
    "oauth-metadata-url-https": lambda d: put(
        scheme(d, "oauth"), "oauth2MetadataUrl", "http://auth.example.com/.well-known/oauth-authorization-server"
    ),
    "oauth-pkce-required.false": lambda d: put(oauth_flows(d)["authorizationCode"], "pkceRequired", False),
    "oauth-pkce-required.missing": lambda d: oauth_flows(d)["authorizationCode"].pop("pkceRequired"),
    "oauth-flows-json-camel-case": lambda d: rename(oauth_flows(d), "authorizationCode", "authorization_code"),
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/oauth-flows-json-camel-case: no rule named oauth-flows-json-camel-case in ruleset.yaml`.

If any of these fixtures fails with `example-validation-error` instead (for example because the v1 schema rejects a `flows` object holding only `implicit`/`password`), read the schema at `~/.cache/p4a-a2a-cli/node_modules/**/a2a*v1*.json`, fix the mutation to the schema's shape, and ledger a ruling.

- [ ] **Step 3: GREEN.**

Add under `violation:`:

```yaml
  - oauth-flows-json-camel-case
  - oauth-metadata-url-https
  - oauth-no-implicit-flow
  - oauth-no-password-flow
```

Add under `warning:`:

```yaml
  - oauth-pkce-required
```

Append under `validations:`:

```yaml
  oauth-no-implicit-flow:
    message: This OAuth 2.0 scheme declares the implicit flow, which is deprecated. Replace it with authorizationCode with PKCE.
    documentation: |
      The implicit flow returns access tokens in the browser redirect, where they leak through
      history, referrers and logs. OAuth 2.0 Security Best Current Practice deprecates it, and
      A2A v1.0 marks it deprecated.
    examples:
      valid: |
        {"oauth2SecurityScheme": {"flows": {"authorizationCode": {"authorizationUrl": "https://auth.example.com/authorize", "tokenUrl": "https://auth.example.com/token", "scopes": {}, "pkceRequired": true}}}}
      invalid: |
        {"oauth2SecurityScheme": {"flows": {"implicit": {"authorizationUrl": "https://auth.example.com/authorize", "scopes": {}}}}}
    targetClass: core.oauth2SecurityScheme
    propertyConstraints:
      core.flows / core.implicit:
        maxCount: 0
  oauth-no-password-flow:
    message: This OAuth 2.0 scheme declares the password flow, which is deprecated. Replace it with authorizationCode, clientCredentials or deviceCode.
    documentation: |
      The resource owner password flow hands the user's password to the client. OAuth 2.0
      Security Best Current Practice forbids it, and A2A v1.0 marks it deprecated.
    examples:
      valid: |
        {"oauth2SecurityScheme": {"flows": {"clientCredentials": {"tokenUrl": "https://auth.example.com/token", "scopes": {}}}}}
      invalid: |
        {"oauth2SecurityScheme": {"flows": {"password": {"tokenUrl": "https://auth.example.com/token", "scopes": {}}}}}
    targetClass: core.oauth2SecurityScheme
    propertyConstraints:
      core.flows / core.password:
        maxCount: 0
  oauth-metadata-url-https:
    message: This OAuth 2.0 scheme's `oauth2MetadataUrl` does not start with https://. Publish the authorization server metadata over TLS.
    documentation: |
      Clients discover the token and authorization endpoints from oauth2MetadataUrl
      (RFC 8414). Over plain HTTP an attacker can swap in their own endpoints and harvest
      credentials. RFC 8414 requires TLS for the metadata document.
    examples:
      valid: |
        {"oauth2SecurityScheme": {"oauth2MetadataUrl": "https://auth.example.com/.well-known/oauth-authorization-server"}}
      invalid: |
        {"oauth2SecurityScheme": {"oauth2MetadataUrl": "http://auth.example.com/.well-known/oauth-authorization-server"}}
    targetClass: core.oauth2SecurityScheme
    propertyConstraints:
      core.oauth2MetadataUrl:
        pattern: "^https://"
  oauth-pkce-required:
    message: This OAuth 2.0 scheme's authorizationCode flow does not set `pkceRequired` to true. Require PKCE at the authorization server and set pkceRequired to true.
    documentation: |
      PKCE stops intercepted authorization codes from being redeemed. OAuth 2.0 Security Best
      Current Practice recommends it for every client. A2A v1.0 exposes pkceRequired so
      clients know to send a code challenge.
    examples:
      valid: |
        {"authorizationCode": {"authorizationUrl": "https://auth.example.com/authorize", "tokenUrl": "https://auth.example.com/token", "scopes": {}, "pkceRequired": true}}
      invalid: |
        {"authorizationCode": {"authorizationUrl": "https://auth.example.com/authorize", "tokenUrl": "https://auth.example.com/token", "scopes": {}}}
    targetClass: core.oauth2SecurityScheme
    if:
      propertyConstraints:
        core.flows / core.authorizationCode:
          minCount: 1
    then:
      propertyConstraints:
        core.flows / core.authorizationCode / core.pkceRequired:
          minCount: 1
          in: [true]
  oauth-flows-json-camel-case:
    message: This OAuth 2.0 scheme's flows use authorization_code, client_credentials or device_code. Rename them to authorizationCode, clientCredentials or deviceCode; snake_case hides the flow from clients and from the PKCE rule.
    documentation: |
      A2A v1.0 JSON MUST use camelCase. Anypoint's card schema accepts snake_case flow names but
      stores them under a different name. Clients then don't see the flow, and the PKCE rule
      can't check it.
    examples:
      valid: |
        {"flows": {"authorizationCode": {"pkceRequired": true}}}
      invalid: |
        {"flows": {"authorization_code": {"pkce_required": false}}}
    targetClass: core.oauth2SecurityScheme
    propertyConstraints:
      core.flows / core.authorization_code:
        maxCount: 0
      core.flows / core.client_credentials:
        maxCount: 0
      core.flows / core.device_code:
        maxCount: 0
```

Run: `scripts/check.sh`
Expected:
- each new fixture gives only its own ID; both `oauth-pkce-required` variants give `oauth-pkce-required:Warning`;
- `fixtures/scope/v03-card` and `fixtures/scope/mcp-manifest` (both with implicit/password flows) still give 0 findings;
- `ALL CHECKS PASSED`.

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: OAuth flow, metadata and PKCE rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `oidc-url-https`, `api-key-not-in-query`, `card-signed`, `card-security-json-camel-case`

**Files:**
- Modify: `scripts/fixtures.py` (`BAD`, `EXPECTED`), `ruleset.yaml`

- [ ] **Step 1: Add the bad fixtures.** Append to `BAD`:

```python
    "oidc-url-https": lambda d: put(
        scheme(d, "oidc"), "openIdConnectUrl", "http://id.example.com/.well-known/openid-configuration"
    ),
    "oidc-url-https.missing": lambda d: scheme(d, "oidc").pop("openIdConnectUrl"),
    # Review Focus 4: the snake_case alias reads as a missing openIdConnectUrl.
    "oidc-url-https.snake-case": lambda d: rename(scheme(d, "oidc"), "openIdConnectUrl", "open_id_connect_url"),
    "api-key-not-in-query": lambda d: put(scheme(d, "key"), "location", "query"),
    "card-signed": lambda d: d.pop("signatures"),
    "card-security-json-camel-case": lambda d: rename(d, "supportedInterfaces", "supported_interfaces"),
    "card-security-json-camel-case.security-requirements": lambda d: rename(
        d, "securityRequirements", "security_requirements"
    ),
```

Add to `EXPECTED`:

```python
    "card-security-json-camel-case.security-requirements": [
        "card-security-json-camel-case:Violation",
        "card-security-declared:Warning",
        "extended-card-requires-auth:Violation",
    ],
```

- [ ] **Step 2: RED**

Run: `python3 -I scripts/fixtures.py && scripts/check.sh`
Expected: `FAIL: fixtures/bad/api-key-not-in-query: no rule named api-key-not-in-query in ruleset.yaml`.

- [ ] **Step 3: GREEN.**

Add under `violation:`:

```yaml
  - card-security-json-camel-case
  - oidc-url-https
```

Add under `warning:`:

```yaml
  - api-key-not-in-query
```

Add a new `info:` list after `warning:`:

```yaml
info:
  - card-signed
```

Append under `validations:`:

```yaml
  oidc-url-https:
    message: This OpenID Connect scheme has no `openIdConnectUrl`, or it does not start with https://. Set the https URL of the OpenID Provider discovery document.
    documentation: |
      Clients fetch issuer, keys and endpoints from openIdConnectUrl. A2A v1.0 marks it
      REQUIRED, and OpenID Connect Discovery requires TLS. Over plain HTTP an attacker can
      substitute signing keys and forge identities. A snake_case `open_id_connect_url` also
      fails this rule, because clients don't read it.
    examples:
      valid: |
        {"openIdConnectSecurityScheme": {"openIdConnectUrl": "https://id.example.com/.well-known/openid-configuration"}}
      invalid: |
        {"openIdConnectSecurityScheme": {"openIdConnectUrl": "http://id.example.com/.well-known/openid-configuration"}}
    targetClass: core.openIdConnectSecurityScheme
    propertyConstraints:
      core.openIdConnectUrl:
        minCount: 1
        pattern: "^https://"
  api-key-not-in-query:
    message: This API key scheme sends the key in the query string. Set `location` to header (or cookie), because query strings end up in logs, proxies and browser history.
    documentation: |
      URLs are logged by gateways, proxies and servers and kept in browser history, so a key in
      the query string leaks far beyond the agent. Send it in a header instead.
    examples:
      valid: |
        {"apiKeySecurityScheme": {"location": "header", "name": "X-API-Key"}}
      invalid: |
        {"apiKeySecurityScheme": {"location": "query", "name": "api_key"}}
    targetClass: core.apiKeySecurityScheme
    propertyConstraints:
      core.location:
        in: [header, cookie]
  card-signed:
    message: Agent Card has no `signatures`. Sign the card (JWS over the JCS-canonicalized card) so clients can verify it was not tampered with.
    documentation: |
      A2A v1.0 lets publishers sign the Agent Card with JWS. A signed card lets clients detect
      a card altered in transit or in a registry, for example one pointing at an attacker's
      URL. This rule checks presence only; verifying the signature is a runtime concern. This
      finding is reported on the asset, not on a line of the card.
    examples:
      valid: |
        {"signatures": [{"protected": "eyJhbGciOiJFUzI1NiJ9", "signature": "c2lnbmF0dXJl"}]}
      invalid: |
        {"name": "Weather Agent"}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.signatures:
          minCount: 1
  card-security-json-camel-case:
    message: Agent Card uses supported_interfaces, security_schemes or security_requirements. Rename them to camelCase, because snake_case hides interfaces and schemes from clients and from every safety rule.
    documentation: |
      A2A v1.0 JSON MUST use camelCase. Anypoint's card schema accepts these snake_case aliases
      but stores them under different names, so an http interface or a weak scheme behind them
      passes every other safety rule unseen. This finding is reported on the asset, not on a
      line of the card.
    examples:
      valid: |
        {"supportedInterfaces": [{"url": "https://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}]}
      invalid: |
        {"supported_interfaces": [{"url": "http://agent.example.com/a2a", "protocolBinding": "JSONRPC", "protocolVersion": "1.0"}]}
    targetClass: api.Project
    if:
      propertyConstraints:
        catalog.classifier:
          in: [a2a-v1-card]
    then:
      propertyConstraints:
        api.contract / doc.encodes / core.supported_interfaces:
          maxCount: 0
        api.contract / doc.encodes / core.security_schemes:
          maxCount: 0
        api.contract / doc.encodes / core.security_requirements:
          maxCount: 0
```

Run: `scripts/check.sh`
Expected: `card-signed -> card-signed:Info`; the three-ID `expected` fixture passes; `ALL CHECKS PASSED`. The safety ruleset now has 12 rules (`defined_ids | wc -l` = 12).

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures.py ruleset.yaml fixtures
git commit -m "feat: OIDC, API key, signing and camelCase safety rules

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Safety README, CHANGELOG, cross-checks, container docs, push

**Files:**
- Create: `README.md`, `CHANGELOG.md` (safety repo)
- Modify: `../CLAUDE.md` (the container, not git)

- [ ] **Step 1: Write `README.md`**

````markdown
# A2A Agent Safety ruleset

A MuleSoft API Governance ruleset (AMF Validation Profile 1.0) for **A2A v1.0 Agent Cards**:
Exchange assets with classifier `a2a-v1-card`. It checks that the card publishes
only secure ways to reach and authenticate to the agent.

**Pairs with:**
- [A2A Agent Card Conformance](https://github.com/P4A-Policies-for-Agents/a2a-agent-card-conformance-ruleset),
  for the fields A2A v1.0 marks REQUIRED.
- MuleSoft's *Agent Network Best Practices*, for Agent Network specs.

## Rules

| Rule | Severity | Why | Fix |
|---|---|---|---|
| `interface-url-https` | violation | Production MUST use encrypted transport | Serve every interface on `https://` |
| `extended-card-requires-auth` | violation | The extended card MUST be fetched with authentication | Declare `securitySchemes` and `securityRequirements` |
| `oauth-no-implicit-flow` | violation | Implicit flow leaks tokens; deprecated | Use `authorizationCode` with PKCE |
| `oauth-no-password-flow` | violation | Password flow hands passwords to clients; deprecated | Use `authorizationCode`, `clientCredentials` or `deviceCode` |
| `oauth-metadata-url-https` | violation | Metadata over HTTP lets attackers swap endpoints | Use an `https://` `oauth2MetadataUrl` |
| `oidc-url-https` | violation | Discovery over HTTP lets attackers swap keys | Set an `https://` `openIdConnectUrl` |
| `card-security-json-camel-case` | violation | snake_case hides interfaces and schemes from every rule | Use camelCase |
| `oauth-flows-json-camel-case` | violation | snake_case hides flows from the PKCE rule | Use camelCase flow names |
| `card-security-declared` | warning | Clients can't discover how to authenticate | Declare `securitySchemes` and `securityRequirements` |
| `oauth-pkce-required` | warning | Intercepted codes can be redeemed without PKCE | Set `pkceRequired: true` |
| `api-key-not-in-query` | warning | Query strings end up in logs | Send the key in a header |
| `card-signed` | info | Unsigned cards can be altered undetected | Add a JWS `signatures` entry |

## Deploy it to your org

Find this ruleset in the [P4A catalog](https://www.p4a.ai) and deploy it to your Anypoint org,
either with **Publish to Exchange** or with the P4A MCP server's `deploy_ruleset`. Then apply it
through a governance profile that covers your A2A agent card assets.

## Limitations

- **Hosted support is unverified.** Validating `a2a-v1-card` assets needs governance plugin
  1.1.4 or later. It isn't yet confirmed that Anypoint's hosted governance validates these
  assets.
- **Card-level findings have no source location.** `extended-card-requires-auth`,
  `card-security-declared`, `card-signed` and `card-security-json-camel-case` are reported on
  the asset, so their messages name the field.
- **`securityRequirements` can't be checked against `securitySchemes` names.** Scheme names are
  map keys, which a validation profile can't join on.
- **Signatures are checked for presence only.** JWS verification is a runtime concern.
- **`interface-url-https` also flags local development cards.** That is intended for governed
  Exchange assets.
- **snake_case scheme wrappers aren't detected.** `api_key_security_scheme` and
  `open_id_connect_security_scheme` sit under user-chosen scheme names, so a card using them
  evades `api-key-not-in-query` and `oidc-url-https`.
- **`validate-authoring` false errors.** It has no A2A domain, so it reports `Invalid
  targetClass` for `core.supportedInterfaces`, `core.oauth2SecurityScheme`,
  `core.apiKeySecurityScheme` and `core.openIdConnectSecurityScheme`.
  `governance:ruleset:validate` accepts the ruleset, and the fixtures prove each rule.

## Development

`scripts/check.sh` needs governance plugin **1.1.4 or later**. One way to install it without
touching your global CLI:

```bash
mkdir -p ~/.cache/p4a-a2a-cli && cd ~/.cache/p4a-a2a-cli
echo '{"private":true,"dependencies":{"anypoint-cli-v4-public":"1.6.27"},"overrides":{"mulesoft-anypoint-cli-governance-plugin":"1.1.4"}}' > package.json
npm install --no-audit --no-fund
```

Then, from the repo root:

```bash
python3 -I scripts/fixtures.py
ANYPOINT_CLI=~/.cache/p4a-a2a-cli/node_modules/.bin/anypoint-cli-v4 scripts/check.sh
```

- `scripts/fixtures.py` generates every fixture. Its `GOOD` card and scope documents are
  identical in both A2A ruleset repos. Never edit `fixtures/` by hand.
- Bump `version` in `exchange.json` for every rule change.

## Source Ref

A2A Protocol Specification 1.0.0, https://a2a-protocol.org/latest/specification/ (snapshot
2026-10-09).
````

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## 1.0.0 (2026-10-09)

- Initial release: 12 safety rules for A2A v1.0 Agent Cards (8 violations, 3 warnings, 1 info).
```

- [ ] **Step 3: Cross-checks**

```bash
scripts/check.sh 2>&1 | tail -1
(cd ../a2a-agent-card-conformance-ruleset && scripts/check.sh 2>&1 | rg 'a2a-agent-safety-ruleset/fixtures/good|ALL CHECKS')
diff <(sed -n '/^# --- Keep everything/,/^# --- per-repo/p' scripts/fixtures.py) \
     <(sed -n '/^# --- Keep everything/,/^# --- per-repo/p' ../a2a-agent-card-conformance-ruleset/scripts/fixtures.py) && echo shared-identical
diff <(sed '/^# --- per-repo config ---$/,/^# -----------------------$/d' scripts/check.sh) \
     <(sed '/^# --- per-repo config ---$/,/^# -----------------------$/d' ../a2a-agent-card-conformance-ruleset/scripts/check.sh) && echo harness-identical
rg -n 'mulesoft-emu|/Users/' README.md ruleset.yaml scripts || echo clean
```

Expected:
- `ALL CHECKS PASSED`.
- `PASS: ../a2a-agent-safety-ruleset/fixtures/good: 0 findings` and `ALL CHECKS PASSED`.
- `shared-identical`, `harness-identical`, `clean`.

- [ ] **Step 4: Update the container `CLAUDE.md`**

Add two rows to the repo table in `ms-omni-governance-rulesets/CLAUDE.md`:

```markdown
| `a2a-agent-card-conformance-ruleset/` | A2A v1.0 Agent Card REQUIRED-field conformance. Holds the A2A spec and plan. |
| `a2a-agent-safety-ruleset/` | Safety checks for A2A v1.0 Agent Cards. |
```

Append:

```markdown
## A2A v1 gotchas (verified with governance plugin 1.1.4)

- `classifier: a2a-v1-card` is only parsed by plugin ≥ 1.1.4 (CLI 1.6.27 with an npm override).
  The global CLI is too old; see either A2A README "Development".
- The card is a generic graph. Fields are `core.<jsonName>`, and each nested object's class is
  `core.<jsonKey>` (`core.skills`, `core.oauth2SecurityScheme`, …). The project node is
  `api.Project` (`catalog.classifier`, `api.contract / doc.encodes` → card root).
- `core.encodes`, `core.provider`, `core.capabilities` and `core.flows` collide with MCP manifests
  and v0.3 cards. Guard card-level rules on `api.Project` with `if: catalog.classifier in
  [a2a-v1-card]`. Those findings have no source range.
- Flat paths aggregate across elements. Use per-element `targetClass` instead.
  `validate-authoring` rejects those targetClasses; `governance:ruleset:validate` accepts them.
- Nested `propertyConstraints` under an `api.Project` path breaks every document.
- `in:` ignores missing values, so pair it with `minCount: 1`.
- snake_case aliases are accepted and not normalized, so camelCase rules are needed.
- A rule with N failing paths reports N results.
```

- [ ] **Step 5: Commit and push**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: README and CHANGELOG

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
direnv exec . git push -u origin main
```

Expected: the push succeeds. **Stop here.**
- No `v1.0.0` tag.
- No P4A `submit_policy`, tier-2 `validate_ruleset` or `deploy_ruleset`.
- Report the results to the user and wait for their go.

---

## After the plan (not tasks; each needs the user's explicit go)

1. Tag `v1.0.0` in both repos.
2. Submit each ruleset to P4A (one approval each) with:
   - `targetScopes: ["agent-network"]`
   - tags `a2a`, `agent`, plus `conformance` or `security`
   - `examplesUrl` pointing to `…/tree/main/fixtures`
   - `sourceRef` `v1.0.0`
3. Dogfood: `deploy_ruleset` into our own test org (approved separately), plus a **draft** console profile on a published v1 card. This settles hosted support.

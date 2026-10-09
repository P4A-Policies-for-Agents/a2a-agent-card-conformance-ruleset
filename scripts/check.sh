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

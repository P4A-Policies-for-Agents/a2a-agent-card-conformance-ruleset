#!/usr/bin/env bash
# Publishes this ruleset's example documents to the Exchange business group in .env, so you can
# test the ruleset on real assets: <prefix>-ok (expect 0 findings) and <prefix>-<rule-id> (expect
# exactly that rule). Asset types follow each fixture's exchange.json classifier.
# Usage: scripts/publish-examples.sh [--all] [--dry-run]
#   --all      also publish every bad variant and the scope fixtures
#   --dry-run  list what would be published
# Existing asset versions (409) are skipped. Remove everything with scripts/cleanup-examples.sh.
. "$(dirname "$0")/examples-lib.sh"

mode='' dry=''
for a in "$@"; do
  case $a in --all) mode=all ;; --dry-run) dry=1 ;; *) fail "unknown option: $a" ;; esac
done

plan=$(example_plan "$mode")
echo "Target: $ANYPOINT_HOST, business group $ANYPOINT_ORG_ID, version $EXAMPLES_VERSION, $(wc -l <<<"$plan" | tr -d ' ') assets"
if [ -n "$dry" ]; then cut -f1,4 <<<"$plan" | column -t; exit 0; fi

TOKEN=$(token)
out=$(mktemp); trap 'rm -f "$out"' EXIT
published=0 skipped=0 failed=0
while IFS=$'\t' read -r id name desc dir; do
  main=$(jq -r .main "$dir/exchange.json")
  case $(jq -r .classifier "$dir/exchange.json") in
    mcp-metadata) form=(-F type=mcp -F "files.mcp-metadata.json=@$dir/$main;type=application/json") ;;
    a2a-v1-card) form=(-F type=agent -F properties.protocol=a2a_v1 -F "files.a2a-v1-card.json=@$dir/$main;type=application/json") ;;
    a2a-card) form=(-F type=agent -F properties.protocol=a2a -F "files.a2a-card.json=@$dir/$main;type=application/json") ;;
    *) echo "FAIL  $id: unsupported classifier in $dir/exchange.json"; failed=$((failed + 1)); continue ;;
  esac
  code=$(curl -sS -o "$out" -w '%{http_code}' -X POST \
    "$BASE_URL/exchange/api/v2/organizations/$ANYPOINT_ORG_ID/assets/$ANYPOINT_ORG_ID/$id/$EXAMPLES_VERSION" \
    -H "Authorization: Bearer $TOKEN" -H 'x-sync-publication: true' \
    -F "name=$name" -F "description=$desc" -F status=published -F properties.platform=ruleset-examples "${form[@]}")
  case $code in
    20?) echo "OK    $id"; published=$((published + 1)) ;;
    409) echo "SKIP  $id (already exists)"; skipped=$((skipped + 1)) ;;
    *) echo "FAIL  $id: HTTP $code $(jq -c '.details // .message' "$out" 2>/dev/null || head -c 300 "$out")"; failed=$((failed + 1)) ;;
  esac
done <<<"$plan"
echo "published $published, skipped $skipped, failed $failed"
[ "$failed" -eq 0 ]

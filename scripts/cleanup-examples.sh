#!/usr/bin/env bash
# Deletes the example assets that publish-examples.sh creates (with or without --all) from the
# Exchange business group in .env. Only asset IDs this repo's fixtures produce are touched.
# Usage: scripts/cleanup-examples.sh [--dry-run] [--hard] [--yes]
#   --dry-run  list what would be deleted
#   --hard     hard-delete (Exchange allows this only for recently created assets);
#              the default soft delete moves assets to Exchange's trash
#   --yes      skip the confirmation prompt
. "$(dirname "$0")/examples-lib.sh"

dry='' yes='' delete_type=soft-delete
for a in "$@"; do
  case $a in --dry-run) dry=1 ;; --hard) delete_type=hard-delete ;; --yes) yes=1 ;; *) fail "unknown option: $a" ;; esac
done

ids=$(example_plan all | cut -f1)
echo "Target: $ANYPOINT_HOST, business group $ANYPOINT_ORG_ID, version $EXAMPLES_VERSION, up to $(wc -l <<<"$ids" | tr -d ' ') assets ($delete_type)"
if [ -n "$dry" ]; then echo "$ids"; exit 0; fi
if [ -z "$yes" ]; then
  read -r -p "Delete these assets? Type 'delete' to continue: " answer
  [ "$answer" = delete ] || fail "aborted"
fi

TOKEN=$(token)
out=$(mktemp); trap 'rm -f "$out"' EXIT
deleted=0 missing=0 failed=0
while read -r id; do
  code=$(curl -sS -o "$out" -w '%{http_code}' -X DELETE \
    "$BASE_URL/exchange/api/v2/assets/$ANYPOINT_ORG_ID/$id/$EXAMPLES_VERSION" \
    -H "Authorization: Bearer $TOKEN" -H "x-delete-type: $delete_type")
  case $code in
    20?) echo "OK    $id"; deleted=$((deleted + 1)) ;;
    404) missing=$((missing + 1)) ;;
    *) echo "FAIL  $id: HTTP $code $(jq -c '.details // .message' "$out" 2>/dev/null || head -c 300 "$out")"; failed=$((failed + 1)) ;;
  esac
done <<<"$ids"
echo "deleted $deleted, not found $missing, failed $failed"
[ "$failed" -eq 0 ]

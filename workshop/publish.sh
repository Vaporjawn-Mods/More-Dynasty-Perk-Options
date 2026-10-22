#!/bin/bash
# Publishes this mod to its Steam Workshop item (CK3, app 1158310) with steamcmd.
#   ./workshop/publish.sh --dry-run   stage + validate + write the VDF, upload nothing
#   ./workshop/publish.sh             do the above, then upload
# steamcmd needs the cached login (arch -x86_64 steamcmd +login vwizzle12 once), and only runs under Rosetta here.
# steamcmd can only set the MAIN preview image; extra screenshots are added on the Workshop page.
set -euo pipefail
cd "$(dirname "$0")/.."
APPID=1158310
ITEM="3824445454"                      # 0 = create a new Workshop item (the new id is then written into descriptor.mod)
TITLE="More Dynasty Perk Options"
STEAM_USER="${STEAM_USER:-vwizzle12}"
SLUG="more-dynasty-perk-options"
STAGE="$HOME/.cache/ck3-workshop/$SLUG"
VDF="$HOME/.cache/ck3-workshop/$SLUG.vdf"

if [ "$ITEM" != "0" ]; then
  grep -q "remote_file_id=\"$ITEM\"" descriptor.mod || { echo "descriptor.mod remote_file_id is not $ITEM"; exit 1; }
fi
grep -q 'supported_version="1.20' descriptor.mod || { echo "descriptor.mod supported_version is not 1.20.*"; exit 1; }
for f in $(find common localization -type f \( -name '*.txt' -o -name '*.yml' \)); do
  [ "$(head -c 3 "$f" | xxd -p)" = "efbbbf" ] || { echo "missing UTF-8 BOM: $f"; exit 1; }
done

# A straight double quote truncates the description/change note at that point (steamcmd's VDF parsing), so refuse them.
for f in workshop/DESCRIPTION.txt workshop/CHANGENOTES.txt; do
  ! grep -q '"' "$f" || { echo "$f contains a double quote (it would be cut off on Steam); remove it"; exit 1; }
done

rm -rf "$STAGE"; mkdir -p "$STAGE"
rsync -a --exclude '.git' --exclude '.gitattributes' --exclude '.vscode' --exclude 'workshop' --exclude '.DS_Store' ./ "$STAGE/"
{
  echo '"workshopitem"'; echo '{'
  echo "	\"appid\"		\"$APPID\""
  echo "	\"publishedfileid\"		\"$ITEM\""
  echo "	\"contentfolder\"		\"$STAGE\""
  [ "$ITEM" = "0" ] && { echo "	\"title\"		\"$TITLE\""; echo "	\"visibility\"		\"0\""; }
  printf '	"changenote"		"%s"\n' "$(sed 's/"/\\"/g' workshop/CHANGENOTES.txt)"
  printf '	"description"		"%s"\n' "$(sed 's/"/\\"/g' workshop/DESCRIPTION.txt)"
  echo "	\"previewfile\"		\"$PWD/workshop/images/cover.jpg\""
  echo '}'
} > "$VDF"

echo "Staged: $STAGE"; (cd "$STAGE" && find . -type f | sort)
echo "VDF:    $VDF"
[ "${1:-}" = "--dry-run" ] && { echo "Dry run: nothing uploaded."; exit 0; }
arch -x86_64 steamcmd +login "$STEAM_USER" +workshop_build_item "$VDF" +quit
if [ "$ITEM" = "0" ]; then
  NEWID=$(sed -n 's/.*"publishedfileid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$VDF" | head -1)
  if [ -n "$NEWID" ] && [ "$NEWID" != "0" ]; then
    echo "Created Workshop item $NEWID"
    printf 'remote_file_id="%s"\n' "$NEWID" >> descriptor.mod
    echo "Wrote remote_file_id into descriptor.mod; edit ITEM in this script to $NEWID for future updates."
  else
    echo "steamcmd did not report a new item id; check the output above."; exit 1
  fi
fi

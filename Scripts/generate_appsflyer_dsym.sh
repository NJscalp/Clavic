#!/bin/bash
# Erzeugt AppsFlyerLib.framework.dSYM für Xcode-16-Archive-Validierung,
# falls Xcode keine separate dSYM für das eingebettete Framework anlegt.

set -euo pipefail

AF_BINARY="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/AppsFlyerLib.framework/AppsFlyerLib"
AF_DSYM="${DWARF_DSYM_FOLDER_PATH}/AppsFlyerLib.framework.dSYM"

if [[ ! -f "$AF_BINARY" ]]; then
  echo "note: AppsFlyerLib.framework not embedded — skipping dSYM generation."
  exit 0
fi

mkdir -p "${DWARF_DSYM_FOLDER_PATH}"

if [[ -d "$AF_DSYM" ]]; then
  EXISTING_UUID="$(dwarfdump --uuid "$AF_DSYM" 2>/dev/null | awk '/UUID:/ {print $2}' | head -1 || true)"
  BINARY_UUID="$(dwarfdump --uuid "$AF_BINARY" 2>/dev/null | awk '/UUID:/ {print $2}' | head -1 || true)"
  if [[ -n "$EXISTING_UUID" && "$EXISTING_UUID" == "$BINARY_UUID" ]]; then
    echo "note: AppsFlyerLib.framework.dSYM already present (UUID $EXISTING_UUID)."
    exit 0
  fi
  rm -rf "$AF_DSYM"
fi

echo "Generating AppsFlyerLib.framework.dSYM …"
xcrun dsymutil "$AF_BINARY" -o "$AF_DSYM"
dwarfdump --uuid "$AF_DSYM" || true

#!/bin/bash
# Installe ConvertDock dans /Applications et crée un raccourci sur le Bureau.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/build-app.sh

DEST="/Applications/ConvertDock.app"
echo "▸ Installation dans ${DEST}…"
pkill -x ConvertDock 2>/dev/null || true
rm -rf "$DEST"
cp -R build/ConvertDock.app "$DEST"

# Enregistre l'app auprès de LaunchServices (dépôt sur l'icône, service Finder).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
/System/Library/CoreServices/pbs -update 2>/dev/null || true

if [[ "${NO_DESKTOP_ALIAS:-0}" != "1" && ! -e "$HOME/Desktop/ConvertDock" ]]; then
  echo "▸ Raccourci sur le Bureau…"
  osascript -e 'tell application "Finder" to make alias file to POSIX file "/Applications/ConvertDock.app" at desktop' \
    -e 'tell application "Finder" to set name of result to "ConvertDock"' >/dev/null
fi

echo "✓ ConvertDock installé. Déposez un fichier sur son icône !"

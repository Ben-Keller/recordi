#!/bin/bash
# Finder opens .command files in Terminal; users do not need to type commands.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
if /bin/bash "$ROOT/scripts/setup-packaged.sh"; then
  printf '\nSetup finished. You can close this window.\n'
else
  printf '\nSetup stopped. Your recordings have been kept. Read the message above. Details are saved in ~/Library/Application Support/Recordi/setup.log. You can run setup again when ready.\n'
fi
read -r -p 'Press Return to close this window. ' _

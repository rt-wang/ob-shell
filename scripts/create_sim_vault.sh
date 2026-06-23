#!/bin/sh
set -eu

DEVICE_ID="${DEVICE_ID:-}"
VAULT_NAME="${VAULT_NAME:-TestVault}"
RESET="${RESET:-0}"
SIM_DATA="${SIM_DATA:-}"

detect_booted_iphone() {
  xcrun simctl list devices booted 2>/dev/null | awk -F '[()]' '/iPhone/ && /Booted/ { print $2; exit }'
}

detect_available_iphone() {
  xcrun simctl list devices available 2>/dev/null | awk -F '[()]' '/iPhone/ && /(Booted|Shutdown)/ { print $2; exit }'
}

if [ -z "$SIM_DATA" ]; then
  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID="$(detect_booted_iphone || true)"
  fi

  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID="$(detect_available_iphone || true)"
  fi

  if [ -z "$DEVICE_ID" ]; then
    cat >&2 <<EOF
Could not infer an iPhone simulator.

Set DEVICE_ID to a simulator UUID, or set SIM_DATA directly:
  DEVICE_ID=<simulator-uuid> sh scripts/create_sim_vault.sh
  SIM_DATA=<simulator-data-path> sh scripts/create_sim_vault.sh
EOF
    if command -v xcrun >/dev/null 2>&1; then
      printf "\nAvailable devices:\n" >&2
      xcrun simctl list devices available >&2 || true
    fi
    exit 1
  fi

  SIM_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE_ID/data"
fi

APP_GROUP_ROOT="$SIM_DATA/Containers/Shared/AppGroup"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

find_local_files_storage() {
  if [ ! -d "$APP_GROUP_ROOT" ]; then
    return 1
  fi

  for metadata in "$APP_GROUP_ROOT"/*/.com.apple.mobile_container_manager.metadata.plist; do
    if [ ! -f "$metadata" ]; then
      continue
    fi

    identifier="$("$PLIST_BUDDY" -c "Print :MCMMetadataIdentifier" "$metadata" 2>/dev/null || true)"
    if [ "$identifier" = "group.com.apple.FileProvider.LocalStorage" ]; then
      app_group_dir="$(dirname "$metadata")"
      printf "%s\n" "$app_group_dir/File Provider Storage"
      return 0
    fi
  done

  return 1
}

LOCAL_FILES="${LOCAL_FILES:-$(find_local_files_storage || true)}"

if [ -z "$LOCAL_FILES" ]; then
  cat >&2 <<EOF
Could not find simulator local Files storage.

Check that this simulator exists and has been booted at least once:
  DEVICE_ID=${DEVICE_ID:-<not set>}
  SIM_DATA=$SIM_DATA

Available devices:
  xcrun simctl list devices available
EOF
  exit 1
fi

VAULT="$LOCAL_FILES/$VAULT_NAME"

case "$RESET" in
  1|true|TRUE|yes|YES)
    if [ -n "$VAULT" ] && [ "$VAULT" != "/" ]; then
      rm -rf "$VAULT"
    fi
    ;;
esac

mkdir -p \
  "$VAULT/Projects/Fast Mobile" \
  "$VAULT/Daily" \
  "$VAULT/.obsidian" \
  "$VAULT/attachments"

cat > "$VAULT/Inbox.md" <<'EOF'
# Inbox

## 2026-06-22 16:30

This is a quick capture test.
EOF

cat > "$VAULT/Projects/Fast Mobile/Launch notes.md" <<'EOF'
# Launch notes

Writing is thinking.

## The clarity loop

You do not think first and then write. You write to think.

- Put the idea on the page
- See what it really means
- Refine, connect, deepen

This line has **bold**, *italic*, __underlined__, and `inline code`.
EOF

cat > "$VAULT/Projects/Fast Mobile/Reading queue.md" <<'EOF'
# Reading queue

## File workflows

Review how simulator local files are exposed through the picker.

1. Create the test vault
2. Pick it from Files
3. Confirm rendered Markdown
EOF

cat > "$VAULT/Daily/2026-06-22.md" <<'EOF'
# June 22, 2026

## Notes

- Test rendered Markdown
- Confirm quick capture append
- Save an edited note
EOF

cat > "$VAULT/.obsidian/config.md" <<'EOF'
# Should be ignored

This file verifies the scanner skips Obsidian internals.
EOF

cat > "$VAULT/attachments/image-note.md" <<'EOF'
# Should also be ignored

This file verifies the scanner skips common attachment folders.
EOF

cat <<EOF
Created simulator test vault:
  $VAULT

In the app:
  1. If no vault is selected, tap Choose Vault Folder.
  2. If another vault is selected, tap the folder icon, then the gear or folder-plus icon.
  3. Open Browse.
  4. Choose On My iPhone / local simulator storage.
  5. Select $VAULT_NAME.

Options:
  DEVICE_ID=<simulator-uuid> sh scripts/create_sim_vault.sh
  VAULT_NAME=AnotherVault sh scripts/create_sim_vault.sh
  RESET=1 sh scripts/create_sim_vault.sh
EOF

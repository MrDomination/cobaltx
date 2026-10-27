#!/bin/bash
ROOT_UUID=$(findmnt -no UUID /)

# Find all systemd-boot entry files, wherever they are
ENTRIES_DIR=""
for path in /boot/loader/entries /boot/efi/loader/entries /efi/loader/entries; do
    if [ -d "$path" ]; then
        ENTRIES_DIR="$path"
        break
    fi
done

if [ -z "$ENTRIES_DIR" ]; then
    echo "No systemd-boot entries directory found, searching..."
    ENTRIES_DIR=$(find / -type d -name "entries" -path "*/loader/*" 2>/dev/null | head -1)
fi

if [ -z "$ENTRIES_DIR" ]; then
    echo "Could not find boot entries anywhere"
    exit 0
fi

echo "Using entries dir: $ENTRIES_DIR"

for entry in "$ENTRIES_DIR"/*.conf; do
    [ -f "$entry" ] || continue
    if ! grep -q "root=" "$entry"; then
        echo "options root=UUID=$ROOT_UUID rw" >> "$entry"
        echo "Fixed: $entry"
    fi
done

exit 0

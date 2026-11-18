#!/bin/bash
set -euo pipefail

project="$(cd "$(dirname "$0")" && pwd)"
app="$project/build/Cuecard.app"
if [ ! -d "$app" ]; then
    echo "Run ./build.sh before packaging." >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$app"
work="$(/usr/bin/mktemp -d "$project/.package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
/usr/bin/ditto -c -k --keepParent "$app" "$work/Cuecard.zip"
/usr/bin/base64 -b 76 -i "$work/Cuecard.zip" -o "$work/payload"
while IFS= read -r line; do
    if [ "$line" = '@BUNDLE_PAYLOAD@' ]; then
        /bin/cat "$work/payload"
        printf '\n'
    else
        printf '%s\n' "$line"
    fi
done < "$project/Tools/installer.template" > "$work/install-cuecard.command"
/bin/bash -n "$work/install-cuecard.command"
chmod 755 "$work/install-cuecard.command"
mv -f "$work/install-cuecard.command" "$project/build/install-cuecard.command"
echo "Packaged $project/build/install-cuecard.command"

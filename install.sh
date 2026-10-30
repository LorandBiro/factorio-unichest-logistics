#!/usr/bin/env bash
# Rebuild the mod zip and install it into the Factorio mods folder.
# Usage: ./install.sh
#   FACTORIO_MODS=/path/to/mods  to override the mods folder location.
set -euo pipefail

cd "$(dirname "$0")"

# Read mod name and version from info.json (no jq/python required).
info_get() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" info.json | head -1
}
name=$(info_get name)
version=$(info_get version)
if [ -z "$name" ] || [ -z "$version" ]; then
  echo "error: could not read name/version from info.json" >&2
  exit 1
fi

mods_dir=${FACTORIO_MODS:-"$HOME/.factorio/mods"}
zip_path="$mods_dir/${name}_${version}.zip"

# Stage the mod files under name_version/, as Factorio expects inside the zip.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stage="$tmp/${name}_${version}"
mkdir -p "$stage"
find . -mindepth 1 -maxdepth 1 \
  ! -name '.git' \
  ! -name '*.zip' \
  ! -name 'install.sh' \
  -exec cp -r {} "$stage/" \;

mkdir -p "$mods_dir"
rm -f "$zip_path"
(cd "$tmp" && zip -qr "$zip_path" "${name}_${version}")

echo "installed ${name}_${version} -> $zip_path"

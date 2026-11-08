#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.0.0}"
VERSION="${VERSION#v}"

echo "==> Building AIQuotaBar v$VERSION..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$DIR/Info.plist"
zsh "$DIR/build.sh"

mkdir -p "$DIR/dist"
ZIP_PATH="$DIR/dist/AIQuotaBar.zip"
rm -f "$ZIP_PATH"

echo "==> Packaging $ZIP_PATH..."
ditto -c -k --keepParent "$DIR/build/AIQuotaBar.app" "$ZIP_PATH"

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "==> SHA256: $SHA"

# Update version and sha256 in Casks/ai-quota-bar.rb
if [ -f "$DIR/Casks/ai-quota-bar.rb" ]; then
  sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$DIR/Casks/ai-quota-bar.rb"
  sed -i '' "s/sha256 .*/sha256 \"$SHA\"/" "$DIR/Casks/ai-quota-bar.rb"
  echo "==> Updated Casks/ai-quota-bar.rb with v$VERSION and sha256"
fi

echo ""
echo "Ready! To publish to GitHub Releases (if using GitHub CLI 'gh'):"
echo "  git add . && git commit -m 'Release v$VERSION' && git push"
echo "  gh release create v$VERSION dist/AIQuotaBar.zip --title 'v$VERSION' --notes 'AIQuotaBar v$VERSION'"

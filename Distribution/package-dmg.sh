#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
package_app="${1:?用法：package-dmg.sh /path/to/NotepadPlus.app [输出目录]}"
package_output_dir="${2:-$package_root/dist}"
package_info="$package_app/Contents/Info.plist"
package_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_info")"
package_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$package_info")"
package_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$package_info")"

if [[ "$package_identifier" != 'com.wanglp.notepadplus' ]]; then
    printf '请使用正式 Bundle ID 的 Release 构建：%s\n' "$package_identifier" >&2
    exit 1
fi
package_architectures="$(lipo -archs "$package_app/Contents/MacOS/NotepadPlus")"
if [[ "$package_architectures" != *arm64* || "$package_architectures" != *x86_64* ]]; then
    printf '安装包需要同时包含 arm64 与 x86_64：%s\n' "$package_architectures" >&2
    exit 1
fi

package_temporary="$(mktemp -d /tmp/notepadplus-package.XXXXXX)"
package_mounted=false
package_verify_mount="$package_temporary/verify"
cleanup_package() {
    if [[ "$package_mounted" == true ]]; then
        hdiutil detach -quiet "$package_verify_mount" || return
    fi
    rm -rf "$package_temporary"
}
trap cleanup_package EXIT
package_stage="$package_temporary/volume"
package_filename="NotepadPlus-$package_version-universal.dmg"
mkdir -p "$package_stage" "$package_output_dir"

ditto "$package_app" "$package_stage/NotepadPlus.app"
# Preserve the application's signing identity. Replacing a Developer ID/App
# Store signature with ad-hoc signing invalidates existing app-scoped grants.
if [[ -n "${NOTEPADPLUS_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$NOTEPADPLUS_CODESIGN_IDENTITY" \
        --entitlements "$package_root/NotepadPlus/NotepadPlus.entitlements" \
        "$package_stage/NotepadPlus.app"
elif codesign -dvv "$package_stage/NotepadPlus.app" 2> "$package_temporary/input-signing.txt" && \
    ! /usr/bin/grep -q 'linker-signed' "$package_temporary/input-signing.txt"; then
    codesign --verify --deep --strict "$package_stage/NotepadPlus.app"
else
    # CODE_SIGNING_ALLOWED=NO can leave only a linker-generated Mach-O seal;
    # this is not a signed application bundle and has no bound entitlements.
    codesign --force --options runtime --sign - \
        --entitlements "$package_root/NotepadPlus/NotepadPlus.entitlements" \
        "$package_stage/NotepadPlus.app"
fi
codesign --verify --deep --strict "$package_stage/NotepadPlus.app"
codesign -dvv -r- "$package_stage/NotepadPlus.app" > "$package_temporary/signing.txt" 2>&1
if /usr/bin/grep -q 'Signature=adhoc' "$package_temporary/signing.txt"; then
    printf '注意：本包使用临时签名，跨版本文件授权可能需要用户重新确认。正式分发请使用同一 Developer ID 签名并公证。\n' >&2
fi
ln -s /Applications "$package_stage/Applications"
ditto "$package_root/Distribution/首次打开说明.txt" "$package_stage/安装说明.txt"
ditto "$package_root/NotepadPlus/CHANGELOG.md" "$package_stage/版本更新记录.md"

# DiskImages preserves signed bundle metadata. makehybrid adds empty FinderInfo
# attributes to every HFS entry, which fails strict code-signature validation.
hdiutil create -srcfolder "$package_stage" -volname "NotepadPlus $package_version" \
    -fs HFS+ -format UDZO "$package_temporary/$package_filename"
hdiutil verify "$package_temporary/$package_filename"
# Verify the actual image, not only the source application before imaging.
mkdir -p "$package_verify_mount"
hdiutil attach -readonly -nobrowse -noautoopen -quiet \
    -mountpoint "$package_verify_mount" "$package_temporary/$package_filename"
package_mounted=true
package_verified_app="$package_verify_mount/NotepadPlus.app"
codesign --verify --deep --strict "$package_verified_app"
lipo "$package_verified_app/Contents/MacOS/NotepadPlus" -verify_arch arm64 x86_64
[[ "$(readlink "$package_verify_mount/Applications")" == /Applications ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$package_verified_app/Contents/Info.plist")" == "$package_identifier" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_verified_app/Contents/Info.plist")" == "$package_version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$package_verified_app/Contents/Info.plist")" == "$package_build" ]]
cmp "$package_root/NotepadPlus/CHANGELOG.md" "$package_verify_mount/版本更新记录.md"
hdiutil detach -quiet "$package_verify_mount"
package_mounted=false
mv -f "$package_temporary/$package_filename" "$package_output_dir/$package_filename"
cp "$package_temporary/signing.txt" "$package_output_dir/$package_filename.signing.txt"
(
    cd "$package_output_dir"
    shasum -a 256 "$package_filename" > "$package_filename.sha256"
)
printf '已生成 NotepadPlus %s（Build %s）：%s/%s\n' \
    "$package_version" "$package_build" "$package_output_dir" "$package_filename"

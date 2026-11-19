#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || $EUID -eq 0 ]]; then
    echo "Usage: bash build.sh NEW_OUTPUT_DIRECTORY (as your desktop user)" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output=$(realpath -m -- "$1")
if [[ -e "$output" || -L "$output" ]]; then
    echo "Choose a new output directory: $output" >&2
    exit 1
fi

version=$(dpkg-query -W -f='${Version}' gnome-control-center)
package_file=$(apt-cache show "gnome-control-center=$version" | sed -n 's/^Filename: //p' | sed -n '1p')
if [[ "$package_file" != pool/*/gnome-control-center_*.deb ]]; then
    echo "The Ubuntu archive no longer indexes GNOME Settings $version. Update Ubuntu before rebuilding." >&2
    exit 1
fi
archive="https://archive.ubuntu.com/ubuntu/${package_file%/*}"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/gnome-settings-external-monitor.XXXXXX")
trap 'status=$?; if (( status != 0 )); then echo "Build logs and files: $work_dir" >&2; fi' EXIT
cd "$work_dir"

echo "Downloading GNOME Settings $version and verifying the source archives."
curl -fsS --retry 2 "$archive/gnome-control-center_${version#*:}.dsc" -o source.dsc
sed -n '/^Checksums-Sha256:/,/^Files:/s/^ \([^ ]*\) [0-9][0-9]* \(.*\)$/\1  \2/p' source.dsc > source.sha256
test -s source.sha256
while read -r _ filename; do
    curl -fsS --retry 2 "$archive/$filename" -o "$filename"
done < source.sha256
sha256sum -c source.sha256
tar -xf gnome-control-center_*.orig.tar.*
source_dir=$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -name 'gnome-control-center-*' -print -quit)
test -n "$source_dir"
tar -xf gnome-control-center_*.debian.tar.* -C "$source_dir"
cd "$source_dir"
while IFS= read -r patch_name; do
    case "$patch_name" in ''|'#'*) continue ;; esac
    patch --batch --forward -s -p1 < "debian/patches/$patch_name"
done < debian/patches/series
git apply "$script_dir/gnome-control-center-external-monitor.patch"

echo "Downloading build tools into a temporary directory."
mkdir -p "$work_dir/debs/partial" "$work_dir/sysroot/usr" "$work_dir/temp"
apt-get -y --download-only -o Debug::NoLocking=true -o Dir::Cache::archives="$work_dir/debs" \
    build-dep . > "$work_dir/apt-download.log" 2>&1
shopt -s nullglob
for archive_file in "$work_dir"/debs/*.deb; do
    dpkg-deb --extract "$archive_file" "$work_dir/sysroot"
done

echo "Building GNOME Settings in a Bubblewrap sandbox."
bwrap --ro-bind / / --overlay-src /usr --overlay-src "$work_dir/sysroot/usr" --ro-overlay /usr \
    --bind "$work_dir" "$work_dir" --proc /proc --dev /dev --unshare-net --unshare-pid --die-with-parent \
    --setenv PATH /usr/bin:/bin --setenv CC /usr/bin/gcc --setenv CXX /usr/bin/g++ \
    --setenv TMPDIR "$work_dir/temp" --chdir "$source_dir" \
    -- /usr/bin/bash -se -- "$HOME/.local/share/gnome-settings-external-monitor/locale" \
    > "$work_dir/build.log" 2>&1 <<'BUILD'
meson setup --prefix=/usr --libexecdir=libexec --buildtype=release --localedir="$1" \
    '-Dc_args=-DSSHD_SERVICE=\"ssh.service\" -DSSHD_SOCKET=\"ssh.socket\"' \
    -Dprivileged_group=sudo -Dlocation-services=enabled -Dwhoopsie=true -Dinsights=true \
    -Dmalcontent=true -Dtests=false -Ddocumentation=false \
    -Ddistributor_logo=/usr/share/pixmaps/ubuntu-logo-text.svg \
    -Ddark_mode_distributor_logo=/usr/share/pixmaps/ubuntu-logo-text-dark.svg \
    _build
ninja -C _build -j 6 shell/gnome-control-center
msgfmt --check po/zh_CN.po -o ../gnome-control-center-2.0.zh_CN.mo
BUILD

mkdir -- "$output"
install -m 0755 _build/shell/gnome-control-center "$output/gnome-control-center"
install -m 0644 "$work_dir/gnome-control-center-2.0.zh_CN.mo" "$output/"
install -m 0644 shell/io.github.orangemiracle.usefulscript.power.gschema.xml "$output/"
printf '%s\n' "$version" > "$output/package-version"
echo "Build complete: $output"
cd "$output"
rm -rf -- "$work_dir"

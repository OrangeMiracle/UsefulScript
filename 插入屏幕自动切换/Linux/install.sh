#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || $EUID -eq 0 ]]; then
    echo "Usage: bash install.sh BUILD_DIRECTORY (as your desktop user)" >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build=$(realpath -- "$1")
version=$(dpkg-query -W -f='${Version}' gnome-control-center)
if [[ $(cat "$build/package-version") != "$version" ]]; then
    echo "Build and Ubuntu package versions differ. Rebuild before installing." >&2
    exit 1
fi

data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
install_dir="$HOME/.local/share/gnome-settings-external-monitor"
launcher="$HOME/.local/bin/gnome-control-center"
dbus_file="$data_home/dbus-1/services/org.gnome.Settings.service"
unit=external-monitor-keep-awake.service
unit_file="$config_home/systemd/user/$unit"
marker='# Managed by UsefulScript GNOME Settings'
schema=io.github.orangemiracle.usefulscript.power

for file in "$launcher" "$dbus_file" "$unit_file"; do
    if [[ -e "$file" || -L "$file" ]] && ! grep -Fxq "$marker" "$file"; then
        echo "Existing user file would be overwritten: $file" >&2
        exit 1
    fi
done
if [[ -e "$install_dir" || -L "$install_dir" ]] && [[ ! -f "$install_dir/package-version" ]]; then
    echo "Existing user directory would be overwritten: $install_dir" >&2
    exit 1
fi

mkdir -p "$HOME/.local/share" "$HOME/.local/bin" "$(dirname "$dbus_file")" "$(dirname "$unit_file")"
stage=$(mktemp -d "$HOME/.local/share/.gnome-settings-external-monitor.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/schemas" "$stage/locale/zh_CN/LC_MESSAGES"
install -m 0755 "$build/gnome-control-center" "$stage/gnome-control-center"
install -m 0644 "$build/$schema.gschema.xml" "$stage/schemas/"
glib-compile-schemas --strict "$stage/schemas"
install -m 0644 "$build/gnome-control-center-2.0.zh_CN.mo" "$stage/locale/zh_CN/LC_MESSAGES/gnome-control-center-2.0.mo"
install -m 0644 "$script_dir/external-monitor-keep-awake.py" "$stage/"
printf '%s\n' "$version" > "$stage/package-version"

if [[ -d "$install_dir" ]]; then
    systemctl --user stop "$unit"
    previous=$(mktemp -d "$HOME/.local/share/.gnome-settings-external-monitor-previous.XXXXXX")
    mv -T "$install_dir" "$previous"
    if ! mv -T "$stage" "$install_dir"; then
        mv -T "$previous" "$install_dir"
        systemctl --user start "$unit"
        exit 1
    fi
    rm -rf -- "$previous"
else
    GSETTINGS_SCHEMA_DIR="$stage/schemas" gsettings reset "$schema" keep-external-monitor-awake
    mv -T "$stage" "$install_dir"
fi

install -m 0755 "$script_dir/gnome-control-center-launcher.sh" "$launcher"
install -m 0644 "$script_dir/$unit" "$unit_file"
printf '%s\n[D-BUS Service]\nName=org.gnome.Settings\nExec="%s" --gapplication-service\n' \
    "$marker" "$launcher" > "$dbus_file"

systemctl --user enable "$unit"
systemctl --user restart "$unit"
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
printf 'Installed GNOME Settings %s for %s. Close and reopen Settings to load it.\n' "$version" "$USER"

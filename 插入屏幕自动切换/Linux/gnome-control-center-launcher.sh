#!/bin/sh
# Managed by UsefulScript GNOME Settings

install_dir="$HOME/.local/share/gnome-settings-external-monitor"
custom_settings="$install_dir/gnome-control-center"
system_settings=/usr/bin/gnome-control-center
service_command=--external-monitor-service

if [ -x "$custom_settings" ] &&
   [ -r "$install_dir/schemas/gschemas.compiled" ] &&
   read -r build_version < "$install_dir/package-version" &&
   system_version=$(/usr/bin/dpkg-query -W -f='${Version}' gnome-control-center) &&
   [ "$system_version" = "$build_version" ]; then
    GSETTINGS_SCHEMA_DIR="$install_dir/schemas"
    export GSETTINGS_SCHEMA_DIR
    if [ "${1:-}" = "$service_command" ]; then
        exec /usr/bin/python3 "$install_dir/external-monitor-keep-awake.py"
    fi
    exec "$custom_settings" "$@"
fi

if [ "${1:-}" = "$service_command" ]; then
    exit 0
fi
exec "$system_settings" "$@"

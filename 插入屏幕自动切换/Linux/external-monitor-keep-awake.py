"""Keep the GNOME session out of idle while an external monitor is active."""

import sys

from gi.repository import Gio, GLib


DISPLAY = "org.gnome.Mutter.DisplayConfig"
DISPLAY_PATH = "/org/gnome/Mutter/DisplayConfig"
SESSION = "org.gnome.SessionManager"
SESSION_PATH = "/org/gnome/SessionManager"
POWER_SCHEMA = "io.github.orangemiracle.usefulscript.power"
KEEP_AWAKE = "keep-external-monitor-awake"
IDLE_INHIBIT = 8
SYSTEM_SETTINGS = "/usr/bin/gnome-control-center"


def main():
    settings = Gio.Settings.new(POWER_SCHEMA)
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    # Release the inhibitor when an Ubuntu update replaces Settings. The
    # launcher will fall back to the system version until the next rebuild.
    system_settings = Gio.File.new_for_path(SYSTEM_SETTINGS).monitor_file(
        Gio.FileMonitorFlags.WATCH_MOVES, None,
    )
    system_settings.connect("changed", lambda *_args: loop.quit())
    no_autostart = Gio.DBusProxyFlags.DO_NOT_AUTO_START
    display = Gio.DBusProxy.new_sync(
        bus, no_autostart | Gio.DBusProxyFlags.GET_INVALIDATED_PROPERTIES,
        None, DISPLAY, DISPLAY_PATH, DISPLAY, None,
    )
    session = Gio.DBusProxy.new_sync(
        bus, no_autostart | Gio.DBusProxyFlags.DO_NOT_LOAD_PROPERTIES,
        None, SESSION, SESSION_PATH, SESSION, None,
    )
    inhibitor_owner = None
    cookie = None
    exit_status = 0

    def session_call(owner, method, parameters, reply_signature):
        return bus.call_sync(
            owner, SESSION_PATH, SESSION, method, parameters,
            GLib.VariantType.new(reply_signature), Gio.DBusCallFlags.NONE,
            5000, None,
        )

    def sync_inhibitor(*_args):
        nonlocal inhibitor_owner, cookie, exit_status
        owner = session.get_name_owner()
        if owner != inhibitor_owner:
            # Each cookie belongs to the session manager that issued it.
            inhibitor_owner, cookie = owner, None

        external = display.get_cached_property("HasExternalMonitor")
        should_inhibit = (
            settings.get_boolean(KEEP_AWAKE)
            and display.get_name_owner() is not None
            and external is not None
            and external.get_boolean()
        )
        try:
            if owner and should_inhibit and cookie is None:
                parameters = GLib.Variant(
                    "(susu)", ("external-monitor-keep-awake", 0,
                               "An external monitor is active", IDLE_INHIBIT),
                )
                cookie = session_call(owner, "Inhibit", parameters, "(u)").unpack()[0]
                print("External monitor active. GNOME idle inhibited.", flush=True)
            elif cookie is not None and not should_inhibit:
                session_call(owner, "Uninhibit", GLib.Variant("(u)", (cookie,)), "()")
                cookie = None
                print("GNOME idle inhibition released.", flush=True)
        except GLib.Error as error:
            # Exiting drops any inhibitor from this connection. systemd retries.
            print(error, file=sys.stderr)
            exit_status = 1
            loop.quit()
        return GLib.SOURCE_REMOVE

    settings.connect(f"changed::{KEEP_AWAKE}", sync_inhibitor)
    display.connect("g-properties-changed", sync_inhibitor)
    display.connect("notify::g-name-owner", sync_inhibitor)
    session.connect("notify::g-name-owner", sync_inhibitor)
    GLib.idle_add(sync_inhibitor)
    loop.run()
    return exit_status


if __name__ == "__main__":
    sys.exit(main())

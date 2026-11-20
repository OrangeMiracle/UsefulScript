import os

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import Gio, GObject, Nautilus


class OpenInVSCode(GObject.GObject, Nautilus.MenuProvider):
    def get_background_items(self, current_folder):
        return self._folder_items(current_folder)

    def get_file_items(self, files):
        if len(files) == 1 and files[0].is_directory():
            return self._folder_items(files[0])
        return []

    def _folder_items(self, folder):
        if folder is None:
            return []

        path = folder.get_location().get_path()
        if not path or not os.path.isdir(path):
            return []

        item = Nautilus.MenuItem(
            name="OpenInVSCode::OpenFolder",
            label="在这里打开 VS Code",
            tip="在 VS Code 中打开此文件夹",
        )
        item.connect("activate", self._open_folder, path)
        return [item]

    @staticmethod
    def _open_folder(_item, path):
        Gio.Subprocess.new(
            ["/snap/bin/code", "--force-user-env", "--new-window", path],
            Gio.SubprocessFlags.NONE,
        )

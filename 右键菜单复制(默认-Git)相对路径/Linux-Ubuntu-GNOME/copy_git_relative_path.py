import os
from pathlib import Path

import gi

gi.require_version("Nautilus", "4.1")
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Nautilus


class CopyGitRelativePath(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        if len(files) != 1:
            return []

        file = files[0]
        location = file.get_location()
        if not location.is_native() or not (path := location.get_path()):
            return []

        is_directory = file.is_directory()
        kind = "文件夹" if is_directory else "文件"
        items = []
        for action, label, copy_parent in (
            ("CopyPath", f"复制{kind}Git相对路径", False),
            ("CopyParent", f"复制{kind}所在目录Git相对路径", True),
        ):
            item = Nautilus.MenuItem(
                name=f"CopyGitRelativePath::{action}",
                label=label,
            )
            item.connect("activate", self._copy_path, Path(path), is_directory, copy_parent)
            items.append(item)
        return items

    def _copy_path(self, _item, path, is_directory, copy_parent):
        try:
            # Git returns a physical worktree path. Resolve ancestors but keep the selected link's name.
            selected = path.parent.resolve() / path.name
            workdir = selected.parent
            if is_directory and not selected.is_symlink():
                workdir = selected

            process = Gio.Subprocess.new(
                ["git", "-C", str(workdir), "rev-parse", "--show-toplevel"],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
            )
        except (GLib.Error, OSError) as error:
            self._show_error(f"无法执行 Git 仓库查询。\n{error}")
            return

        target = selected.parent if copy_parent else selected
        process.communicate_async(None, None, self._copy_when_ready, target)

    def _copy_when_ready(self, process, result, target):
        try:
            _, stdout, _ = process.communicate_finish(result)
        except GLib.Error as error:
            self._show_error(f"无法读取 Git 仓库查询结果。\n{error}")
            return

        if not process.get_successful():
            self._show_error("Git 无法确定所选项目的工作区根目录。")
            return

        root = Path(os.fsdecode(stdout.get_data().removesuffix(b"\n")))
        try:
            relative = target.relative_to(root)
        except ValueError:
            self._show_error("要复制的路径位于所选项目的 Git 工作区之外。")
            return

        text = "." if relative == Path(".") else f"./{relative.as_posix()}"
        try:
            content = Gdk.ContentProvider.new_for_value(GObject.Value(str, text))
        except UnicodeEncodeError:
            self._show_error("路径中有无法作为 UTF-8 文本复制的字符。")
            return

        if not Gdk.Display.get_default().get_clipboard().set_content(content):
            self._show_error("无法写入系统剪贴板。")

    @staticmethod
    def _show_error(detail):
        app = Gtk.Application.get_default()
        window = app.get_active_window() if isinstance(app, Gtk.Application) else None
        Gtk.AlertDialog(message="复制 Git 相对路径失败", detail=detail).show(window)

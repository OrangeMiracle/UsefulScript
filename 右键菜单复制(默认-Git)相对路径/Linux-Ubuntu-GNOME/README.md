# Ubuntu GNOME 右键菜单复制 Git 相对路径

适用于 Ubuntu 26.04 的「文件」（GNOME Nautilus）。扩展使用 Nautilus 4.1 扩展 API 和 GTK 4 剪贴板，适用于 Wayland 和 X11 会话。

## 添加菜单

1. 安装依赖。已安装 `git` 和 `python3-nautilus` 时可跳过此步。

   ```bash
   sudo apt install git python3-nautilus
   ```

2. 在本 README 所在目录打开终端，以当前用户运行下面的命令。扩展将安装到当前账户，重复执行可更新。

   ```bash
   install -Dm644 -- copy_git_relative_path.py \
     "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/copy_git_relative_path.py"
   ```

3. 保存「文件」中正在进行的操作后，运行 `nautilus -q`，再从应用列表重新打开「文件」。

## 使用

在「文件」中右键单个本地文件或文件夹，选择对应菜单项，然后用 `Ctrl+V` 粘贴。以下示例以 Git 工作区根目录下的 `src/demo.py` 和 `src` 为所选项目。

| 右键对象 | 菜单项 | 复制结果 |
| --- | --- | --- |
| `src/demo.py` | 复制文件Git相对路径 | `./src/demo.py` |
| `src/demo.py` | 复制文件所在目录Git相对路径 | `./src` |
| `src` | 复制文件夹Git相对路径 | `./src` |
| `src` | 复制文件夹所在目录Git相对路径 | `.` |

- 路径以 `./` 开头，工作区根目录本身输出 `.`。扩展使用 `git rev-parse --show-toplevel` 定位工作区，也适用于 Git worktree 和子模块。右键符号链接时，复制的是链接条目的路径。
- 复制仓库根文件夹的所在目录时，目标在该工作区之外。遇到这种情况，或 Git 找不到工作区时，扩展会显示提示并保留剪贴板原有内容。

## 卸载

```bash
rm -f -- "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/copy_git_relative_path.py"
nautilus -q
```

重新打开「文件」即可。

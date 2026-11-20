# 在这里打开 VS Code（Linux）

适用于 Ubuntu 的「文件」（GNOME Nautilus）。右键点选菜单项后，VS Code 会在新窗口打开对应的本地文件夹。

## 安装前

在本 README 所在的目录打开终端。两个脚本默认调用 Snap 版 VS Code 的 `/snap/bin/code`。如果你安装的是其他版本，先运行 `command -v code`，再用输出的路径替换所选脚本中的 `/snap/bin/code`。

## 方式一：添加到右键主菜单

使用 `open_in_vscode.py`。它需要支持 Nautilus 4.1 扩展 API 的 `python3-nautilus`。安装系统依赖时需要管理员权限。

```bash
sudo apt install python3-nautilus
install -Dm644 -- open_in_vscode.py \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/open_in_vscode.py"
nautilus -q
```

最后一行会关闭「文件」的所有窗口。从应用菜单重新打开「文件」，然后右键点击**文件夹空白处**或**单个文件夹图标**，选择 **在这里打开 VS Code**。点空白处打开当前文件夹，点图标打开该图标对应的文件夹。

## 方式二：添加到「脚本」子菜单

使用 `nautilus-vscode-script`。Ubuntu 桌面一般已安装此脚本所需的 `python3-gi`，复制到当前账户的脚本目录即可。

```bash
install -Dm755 -- nautilus-vscode-script \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts/在这里打开 VS Code"
```

右键点击**文件夹图标**，选择 **脚本 → 在这里打开 VS Code**。如果菜单还没出现，关闭并重新打开「文件」。

## 卸载

按之前的安装方式执行对应命令。移除主菜单扩展后，重新打开「文件」。

```bash
# 方式一
rm -- "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/open_in_vscode.py"
nautilus -q

# 方式二
rm -- "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts/在这里打开 VS Code"
```

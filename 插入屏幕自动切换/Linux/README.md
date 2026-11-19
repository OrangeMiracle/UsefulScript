# GNOME 外屏常亮

在 Ubuntu 的 **设置 → 电源 → 节电 → 自动熄屏** 下添加 **接入外屏时保持常亮**。第一次安装时开关为关闭。

开启后，只要 GNOME 启用了外屏，就暂停自动熄屏、空闲自动锁屏和未锁屏时的空闲挂起。仍可用 `Super + L` 手动锁屏。拔掉或停用外屏后，GNOME 立即恢复使用「节电」里的当前设置。一旦内屏本身已经空闲超过设定时间，恢复规则时可能立即熄屏。

## 更新后重新安装

此补丁基于 Ubuntu 26.04 LTS（amd64）的 GNOME Settings `1:50.3-0ubuntu0.2`。安装只写入当前用户目录，Ubuntu 提供的 `/usr/bin/gnome-control-center` 仍由 APT 更新。系统包版本变化后，新启动的「设置」会自动使用系统原版，外屏常亮服务也会退出。重建时使用**当前已安装的** Ubuntu 软件包版本。

在桌面会话里打开终端，先关闭已打开的「设置」，然后运行以下命令。构建需要网络、`bubblewrap`、`curl`、`git` 和 `patch`。APT 的构建依赖只下载到临时目录，不需要 `sudo` 安装到系统。

```bash
cd '/home/orange/AI_Project/UsefulScript/插入屏幕自动切换/Linux'
work_dir=$(mktemp -d)
bash build.sh "$work_dir/settings" &&
  bash install.sh "$work_dir/settings"
```

构建时会按 Ubuntu 源码清单验证下载文件，先应用 Ubuntu 的补丁，再应用本目录的 GNOME Settings 补丁。如果新版源码导致补丁无法应用，构建会停止并打印临时目录。在 `gnome-control-center-external-monitor.patch` 适配新版后重新运行即可。安装程序不会用旧版构建产物覆盖新版入口。重新安装会保留你之前选择的开关状态。

完成后重新打开「设置 → 电源 → 节电」。如果原窗口还在，关闭它再打开一次即可载入新程序。

## 验证

开关保持关闭时，外屏按原设定熄屏。需要验证完整行为时，可在接着外屏的情况下打开开关，等待超过当前的熄屏延迟。然后拔掉外屏，内屏应恢复按「节电」设置熄屏。检查后台状态和日志可以运行：

```bash
systemctl --user status external-monitor-keep-awake.service
journalctl --user -u external-monitor-keep-awake.service -n 30
GSETTINGS_SCHEMA_DIR="$HOME/.local/share/gnome-settings-external-monitor/schemas" \
  gsettings get io.github.orangemiracle.usefulscript.power keep-external-monitor-awake
```

## 回退到系统原版

先关闭「设置」窗口。下面的命令会停止用户服务、清除这个开关的值，并移除本项目安装的用户文件。

```bash
systemctl --user disable --now external-monitor-keep-awake.service
GSETTINGS_SCHEMA_DIR="$HOME/.local/share/gnome-settings-external-monitor/schemas" \
  gsettings reset io.github.orangemiracle.usefulscript.power keep-external-monitor-awake
rm -f -- "$HOME/.local/bin/gnome-control-center" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.gnome.Settings.service" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/external-monitor-keep-awake.service"
rm -rf -- "$HOME/.local/share/gnome-settings-external-monitor"
systemctl --user daemon-reload
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
```

重新打开「设置」即使用 Ubuntu 原版。内外屏的布局和缩放仍由 GNOME 自己保存。

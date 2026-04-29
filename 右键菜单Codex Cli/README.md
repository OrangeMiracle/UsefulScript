# 右键菜单：通过 Codex CLI 打开

这是一个用于 Windows 10 / Windows 11 的右键菜单脚本。

安装后，你可以在文件夹空白处、文件夹本身、磁盘盘符上右键，选择：

```text
通过 Codex CLI 打开
```

脚本会在对应目录下打开 PowerShell，并自动执行：

```powershell
codex
```

适合需要频繁在项目目录中启动 Codex CLI 的场景。

---

## 功能说明

支持以下右键位置：

| 右键位置 | 行为 |
|---|---|
| 文件夹空白处右键 | 在当前文件夹打开 PowerShell 并启动 Codex CLI |
| 文件夹本身右键 | 在该文件夹路径打开 PowerShell 并启动 Codex CLI |
| 磁盘盘符右键 | 在该盘符根目录打开 PowerShell 并启动 Codex CLI |

---

## 文件结构

请把这些文件放在同一个目录下：

```text
右键菜单Codex Cli\
├─ Install-OpenCodexHere-v4-copy-icon.ps1
├─ Uninstall-OpenCodexHere-v4-copy-icon.ps1
└─ codex.ico
```

其中：

| 文件 | 作用 |
|---|---|
| `Install-OpenCodexHere-v4-copy-icon.ps1` | 安装右键菜单 |
| `Uninstall-OpenCodexHere-v4-copy-icon.ps1` | 卸载右键菜单 |
| `codex.ico` | 右键菜单使用的自定义图标 |

---

## 图标保存方式

安装时，脚本会自动把当前目录下的：

```text
codex.ico
```

复制到：

```text
%LOCALAPPDATA%\OpenCodexHere\codex.ico
```

通常对应路径为：

```text
C:\Users\你的用户名\AppData\Local\OpenCodexHere\codex.ico
```

这样做的好处是：

- 不依赖原始脚本目录；
- 安装完成后，即使删除原脚本文件夹，右键菜单图标仍然有效；
- 不需要管理员权限；
- 不污染 `C:\Windows\System32` 等系统目录。

---

## 安装方法

在脚本所在目录打开 PowerShell，然后执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Install-OpenCodexHere-v4-copy-icon.ps1 -RestartExplorer
```

参数说明：

| 参数 | 作用 |
|---|---|
| `-RestartExplorer` | 安装后自动重启资源管理器，让右键菜单立即刷新 |

如果不想自动重启资源管理器，也可以执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Install-OpenCodexHere-v4-copy-icon.ps1
```

如果右键菜单没有立即出现，可以手动重启资源管理器，或者注销后重新登录。

---

## 卸载方法

在脚本所在目录打开 PowerShell，然后执行：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Uninstall-OpenCodexHere-v4-copy-icon.ps1 -RestartExplorer
```

默认卸载会移除：

1. 右键菜单注册表项；
2. `%LOCALAPPDATA%\OpenCodexHere` 目录；
3. 已复制的 `codex.ico`；
4. 已安装的 helper 脚本。

---

## 只卸载右键菜单，但保留图标和 helper 文件

如果只想删除右键菜单，不删除本地安装文件，可以执行：

```powershell
.\Uninstall-OpenCodexHere-v4-copy-icon.ps1 -RestartExplorer -KeepFiles
```

---

## Win11 右键菜单说明

Windows 11 使用了新的右键菜单样式。

某些传统注册表右键菜单项可能不会直接显示在第一层菜单，而是出现在：

```text
显示更多选项
```

也可以使用快捷键打开传统右键菜单：

```text
Shift + F10
```

这是 Windows 11 的系统行为，不是脚本错误。

---

## Codex CLI 路径问题

如果点击菜单后提示：

```text
codex command was not found in PATH.
```

说明当前系统环境变量中找不到 `codex` 命令。

常见原因：

1. Codex CLI 没有安装；
2. Codex CLI 已安装，但没有加入 `PATH`；
3. 刚安装 Codex CLI 后，Explorer 还没有刷新环境变量；
4. 当前用户和安装 Codex CLI 的用户不一致。

可以先在普通 PowerShell 中测试：

```powershell
codex --version
```

如果普通 PowerShell 里也无法识别 `codex`，需要先修复 Codex CLI 的安装或环境变量。

如果普通 PowerShell 可以识别，但右键菜单不行，可以尝试：

```powershell
.\Install-OpenCodexHere-v4-copy-icon.ps1 -RestartExplorer
```

或者注销后重新登录。

---

## 安装位置

脚本会写入当前用户注册表，不需要管理员权限。

涉及的注册表位置包括：

```text
HKEY_CURRENT_USER\Software\Classes\Directory\Background\shell\OpenWithCodexCLI
HKEY_CURRENT_USER\Software\Classes\Directory\shell\OpenWithCodexCLI
HKEY_CURRENT_USER\Software\Classes\Drive\shell\OpenWithCodexCLI
```

本地文件安装目录为：

```text
%LOCALAPPDATA%\OpenCodexHere
```

---

## 注意事项

1. 安装时请确保脚本同目录下存在 `codex.ico`。
2. 不建议把图标长期放在桌面或临时目录后直接引用。
3. 不建议把自定义图标放进 `C:\Windows\System32`。
4. 如果更换了 `codex.ico`，请重新运行安装脚本。
5. 如果移动或删除原始脚本目录，不影响已经安装到 `%LOCALAPPDATA%\OpenCodexHere` 的右键菜单功能。

---

## 常见问题

### 1. 为什么图标没有变化？

可能是 Explorer 图标缓存还没刷新。

可以尝试：

```powershell
.\Install-OpenCodexHere-v4-copy-icon.ps1 -RestartExplorer
```

或者注销后重新登录。

---

### 2. 为什么 Win11 第一层右键菜单看不到？

Win11 对右键菜单做了限制，传统注册表菜单项可能会进入“显示更多选项”。

可以使用：

```text
显示更多选项
```

或者：

```text
Shift + F10
```

---

### 3. 可以把菜单项精确放到 VS Code、Cursor、Git Bash 那一组吗？

不能 100% 精确控制。

Windows 会根据注册表位置、扩展类型、应用注册方式和系统排序规则决定菜单位置。

当前脚本已经去掉了 `Position=Top`，因此不会强制置顶，会尽量以自然位置显示在其他开发工具附近。

---

### 4. 是否需要管理员权限？

通常不需要。

脚本写入的是：

```text
HKEY_CURRENT_USER
```

也就是当前用户注册表。

---

### 5. 能不能改成 Windows Terminal 或 PowerShell 7 打开？

可以，但当前版本默认使用系统自带的 Windows PowerShell。

默认行为更兼容 Win10 / Win11，不依赖额外安装 Windows Terminal 或 PowerShell 7。

---

## 适用环境

| 系统 | 支持情况 |
|---|---|
| Windows 10 | 支持 |
| Windows 11 | 支持，但可能显示在“显示更多选项”中 |
| Windows PowerShell 5.1 | 支持 |
| PowerShell 7 | 非必需 |

---

## 简短说明

这个脚本的目标是：

> 在任意项目目录右键，快速以当前目录启动 Codex CLI。

安装后使用流程：

```text
右键文件夹空白处
→ 通过 Codex CLI 打开
→ 自动打开 PowerShell
→ 自动进入当前目录
→ 自动执行 codex
```

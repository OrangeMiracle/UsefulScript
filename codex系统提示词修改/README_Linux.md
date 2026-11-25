# Linux 版 Codex 系统提示词覆盖

本文说明如何在 Linux（Codex CLI 或 Codex Desktop 远程连接 + codex-router）上使用本目录的提示词。原理和文件格式与 Windows 相同，见 [README_Windows.md](README_Windows.md)。

当前已在虚拟机 `dev-local`（Ubuntu，Codex CLI 0.169.0，codex-router 提交 `b86ac06`）上为 GPT-6.2-Astra、GPT-6.2-Sol 和 DeepSeek V4.1 Flash 1017 启用。

## 相关位置

| 内容 | 路径 |
|---|---|
| Codex 配置 | `~/.codex/config.toml`，其中 `model_catalog_json` 指向下面的合并目录 |
| 合并目录（Codex 读取提示词的位置） | `~/.codex/codex-router/merged-models.json` |
| 覆盖文件夹 | `~/.codex/codex-router/prompt-overrides/<模型 slug>/` |
| codex-router 源码 | `~/.local/share/codex-router` |
| codex-router 自带的 Node | `~/.local/share/codex-router-runtime/node-v24.15.0-linux-x64/bin/node` |
| router 服务 | systemd 用户服务 `codex-router.service`，环境变量在 `~/.config/systemd/user/codex-router.service.d/10-flash-only.conf` |
| 加入覆盖前的目录备份 | `~/.codex/codex-router/merged-models.json.pre-prompt-overrides` |

## 首次安装

以下命令在 Windows 的 PowerShell 中执行，通过 `ssh dev-local` 操作虚拟机。

1. 把 Windows 上 router 仓库的覆盖补丁打到 Linux 源码上。两边是同一个提交时补丁可以直接应用，`git apply --check` 失败则说明源码版本不同，需要手动合并。

   ```powershell
   git -C "$env:USERPROFILE\Documents\Codex\codex-router" diff src/catalog.mjs src/paths.mjs > "$env:TEMP\prompt-overrides.patch"
   scp "$env:TEMP\prompt-overrides.patch" dev-local:/tmp/prompt-overrides.patch
   ssh dev-local 'cd ~/.local/share/codex-router && git apply --check /tmp/prompt-overrides.patch && git apply /tmp/prompt-overrides.patch && rm /tmp/prompt-overrides.patch'
   ```

2. 建立覆盖文件夹，再上传主提示词。DeepSeek 的 slug 是 `deepseek/deepseek-flash`，所以对应两层子文件夹。

   ```powershell
   ssh dev-local 'mkdir -p ~/.codex/codex-router/prompt-overrides/{gpt-6.2-astra,gpt-6.2-sol,deepseek/deepseek-flash}'
   foreach ($slug in 'gpt-6.2-astra', 'gpt-6.2-sol', 'deepseek/deepseek-flash') {
     scp .\base_instructions.md "dev-local:~/.codex/codex-router/prompt-overrides/$slug/base_instructions.md"
   }
   ```

   `sub_prompts.md` 是可选的。虚拟机上现有的三份是从各模型自己的原版导出的，不改它们就和原版一致。

3. 重建目录并重启，步骤见下文。

## 修改提示词

1. 编辑本目录的 `base_instructions.md`，再按「首次安装」第 2 步的 `scp` 循环把它上传到三个文件夹。
2. 在虚拟机上重建合并目录：

   ```powershell
   ssh dev-local 'cd ~/.local/share/codex-router && export MODEL_ROUTER_TARGET=codex MODEL_ROUTER_STATE_DIR=$HOME/.codex/codex-router CODEX_ROUTER_STATE_DIR=$HOME/.codex/codex-router CODEX_HOME=$HOME/.codex MODEL_ROUTER_REGISTRY=$HOME/.codex/codex-router/flash-only-registry.json CODEX_BIN=/usr/local/bin/codex && ~/.local/share/codex-router-runtime/node-v24.15.0-linux-x64/bin/node src/catalog.mjs'
   ```

   不要用 `bin/refresh-catalog`。它会重新抓取原生模型目录，其他模型的提示词也会跟着变。

3. 重启 router：

   ```powershell
   ssh dev-local 'systemctl --user restart codex-router && systemctl --user is-active codex-router'
   ```

4. 重启 Codex，让它重新读取目录。
   - Codex CLI：退出正在运行的 `codex`，再重新启动。
   - Codex Desktop 远程连接：虚拟机上的守护进程 `codex app-server --listen unix://` 是 Desktop 通过 SSH 拉起的，`codex app-server daemon restart` 管不到它，会报 "not managed by codex app-server daemon"。先让它正常退出，再完全退出并重新打开 Windows 上的 Codex Desktop。Desktop 重连时会拉起新的守护进程。

     ```powershell
     ssh dev-local 'pkill -TERM -f "[a]pp-server --listen unix://"'
     ```

     模式里的 `[a]` 不能省略。`pkill -f` 按完整命令行匹配，而这条命令是通过 ssh 交给远端 shell 执行的，shell 自己的命令行里就包含这段文字。写成 `[a]pp-server` 后，正则仍然能匹配守护进程，却匹配不到执行它的 shell，否则 shell 会被一起杀掉，ssh 以退出码 255 断开。

## 检查是否生效

```powershell
ssh dev-local 'codex debug models | python3 -c "import json,sys; [print(m[\"slug\"], (m.get(\"base_instructions\") or \"\")[:60]) for m in json.load(sys.stdin)[\"models\"]]"'
```

三个模型应该以 `You are Codex, an avatar of the Omnissiah` 开头，其他模型保持原样。

这只能说明目录已经更新。要确认对话里真正用上了，就开一个新会话测试：

```powershell
ssh dev-local 'cd /tmp && codex exec -m gpt-6.2-astra --skip-git-repo-check -s read-only "用一句话说明你的身份。不要调用任何工具。"'
```

回答中应该自称万机之神欧姆弥赛亚的化身。

Codex 会把会话创建时的系统提示词存进会话记录（rollout 文件中的 `session_meta.base_instructions`），之后一直沿用。替换前就已存在的会话即使继续对话，用的也还是旧提示词，所以测试必须在新会话里做。

## 恢复原版

删除对应模型的文件夹，然后执行「修改提示词」的第 2 到 4 步：

```powershell
ssh dev-local 'rm -r ~/.codex/codex-router/prompt-overrides/gpt-6.2-sol'
```

## 注意

- 补丁只改了 `src/catalog.mjs` 和 `src/paths.mjs`，没有提交。在 `~/.local/share/codex-router` 中 `git pull` 或升级 router 后，需要重新执行「首次安装」第 1 步。
- `install-integrity.json` 只校验 systemd 单元、agent 文件和启动脚本，不校验 `src/`，所以改源码不会被 router 的完整性检查拦下。

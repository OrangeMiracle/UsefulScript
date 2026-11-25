# Codex 系统提示词覆盖

这份提示词把 Codex Desktop 中模型的人设改为「万机之神欧姆弥赛亚的化身」，并重写了写作风格和编程准则，用来减少 GPT-6 系列过度防御、处处加限定语的输出。

目前用于 GPT-6.2-Astra、GPT-6.2-Sol 和 DeepSeek V4.1 Flash 1017（经 [codex-model-router](https://github.com/DrOetker747/codex-model-router) 接入）。

## 文件

| 文件 | 内容 |
|---|---|
| `base_instructions.md` | 主系统提示词，三个模型共用 |
| `sub_prompts.md` | 按场景追加的子提示词，这份取自 GPT-6.2-Astra 原版，未做修改 |
| `README_Linux.md` | 在 Linux（虚拟机 `dev-local`）上安装和更新这份提示词的步骤 |

## 工作原理

Codex 通过 `~/.codex/config.toml` 中的 `model_catalog_json` 读取 codex-router 生成的 `~/.codex/codex-router/merged-models.json`，每个模型的系统提示词就存放在其中。

本机的 codex-router（`C:\Users\Administrator\Documents\Codex\codex-router`）在 `src/catalog.mjs` 中加了 `withPromptOverrides` 一步。每次生成 `merged-models.json` 时，它会到 `~/.codex/codex-router/prompt-overrides/<模型 slug>/` 中查找覆盖文件。

- slug 中的 `/` 对应一层子文件夹，例如 `deepseek/deepseek-flash` 对应 `prompt-overrides/deepseek/deepseek-flash/`。
- `base_instructions.md` 存放纯文本，`base_instructions.json` 存放 JSON 字符串。二者都会同时写入模型的 `base_instructions` 和 `model_messages.instructions_template`。
- `sub_prompts.md` 用 `<!-- ===== model_messages.<键路径> ===== -->` 分隔各段。`sub_prompts.json` 是一个对象，会按键合并进 `model_messages`。只有文件里出现的键会被替换。
- 同名文件同时有 `.md` 和 `.json` 时，优先使用 `.md`。没有覆盖文件夹的模型保持原样。

当前覆盖目录：

```
~/.codex/codex-router/prompt-overrides/
├── gpt-6.2-astra/            base_instructions.md, sub_prompts.md
├── gpt-6.2-sol/              base_instructions.md, sub_prompts.md
└── deepseek/deepseek-flash/  base_instructions.md, sub_prompts.md
```

三个文件夹里的 `base_instructions.md` 都是本目录这一份。`sub_prompts.md` 则是各模型自己的原版子提示词，彼此并不相同，导出后可以直接编辑。

## 修改提示词

1. 编辑本目录的 `base_instructions.md`。
2. 把它复制到要生效的模型文件夹：

   ```powershell
   $overrides = "$env:USERPROFILE\.codex\codex-router\prompt-overrides"
   foreach ($slug in 'gpt-6.2-astra', 'gpt-6.2-sol', 'deepseek\deepseek-flash') {
     Copy-Item .\base_instructions.md "$overrides\$slug\base_instructions.md"
   }
   ```

3. 重建模型目录：

   ```powershell
   $env:MODEL_ROUTER_TARGET = 'codex'
   $env:MODEL_ROUTER_REGISTRY = "$env:USERPROFILE\.codex\codex-router\flash-only-registry.json"
   $env:CODEX_BIN = "$env:LOCALAPPDATA\OpenAI\Codex\bin\2993767bd1dfb009\codex.exe"
   $env:MODEL_ROUTER_STATE_DIR = "$env:USERPROFILE\.codex\codex-router"
   $env:CODEX_ROUTER_STATE_DIR = "$env:USERPROFILE\.codex\codex-router"
   $env:CODEX_HOME = "$env:USERPROFILE\.codex"
   node "$env:USERPROFILE\Documents\Codex\codex-router\src\catalog.mjs"
   ```

   输出中出现 "reusing the cached capture" 属于正常情况，表示原生模型沿用已缓存的目录。

4. 完全退出并重新打开 Codex。

要给其他模型加覆盖，就在 `prompt-overrides` 下按它的 slug 新建文件夹。slug 可以在 `merged-models.json` 中查到。

## 恢复原版

删除对应模型的覆盖文件夹，然后执行上面的第 3、4 步。加入覆盖前的目录备份在 `~/.codex/codex-router/merged-models.json.pre-prompt-overrides`。

## 注意

- `catalog.mjs` 的改动只存在于本机 codex-router 仓库，没有提交。`git pull` 或升级 codex-router 时如果出现冲突或改动被覆盖，需要重新加回这一步。
- `bin/refresh-catalog` 会重新抓取 Codex 的原生模型目录，其他模型的提示词也会随之更新。覆盖步骤仍然生效。
- 主提示词中的 `{{plugin_id}}` 和 `{{connector_id}}` 是 Codex 的模板占位符，修改时需要原样保留。

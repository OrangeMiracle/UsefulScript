# Git 常用命令速查表

以下是 Git 在各种场景中常用的命令。

---

## 开始一个工作区

另见：

```bash
git help tutorial
```

| 命令 | 中文说明 |
|---|---|
| `git clone` | 将一个仓库克隆到新的目录中 |
| `git init` | 创建一个空的 Git 仓库，或重新初始化一个已有仓库 |

---

## 处理当前修改

另见：

```bash
git help everyday
```

| 命令 | 中文说明 |
|---|---|
| `git add` | 将文件内容添加到暂存区 |
| `git mv` | 移动或重命名文件、目录或符号链接 |
| `git restore` | 恢复工作区中的文件 |
| `git rm` | 从工作区和暂存区中删除文件 |

---

## 查看历史与当前状态

另见：

```bash
git help revisions
```

| 命令 | 中文说明 |
|---|---|
| `git bisect` | 使用二分查找定位引入 Bug 的提交 |
| `git diff` | 显示提交之间、提交与工作区之间等差异 |
| `git grep` | 输出匹配指定模式的行 |
| `git log` | 显示提交日志 |
| `git show` | 显示各种 Git 对象的信息 |
| `git status` | 显示工作区状态 |

---

## 增长、标记与调整共同历史

| 命令 | 中文说明 |
|---|---|
| `git backfill` | 在部分克隆中下载缺失的对象 |
| `git branch` | 列出、创建或删除分支 |
| `git commit` | 将修改记录为一次提交 |
| `git history` | **实验性功能**：重写历史 |
| `git merge` | 合并两个或多个开发历史 |
| `git rebase` | 将提交重新应用到另一个基底提交之上 |
| `git reset` | 将 `HEAD` 或暂存区重置到指定状态 |
| `git switch` | 切换分支 |
| `git tag` | 创建、列出、删除或验证标签 |

---

## 协作

另见：

```bash
git help workflows
```

| 命令 | 中文说明 |
|---|---|
| `git fetch` | 从另一个仓库下载对象和引用 |
| `git pull` | 从另一个仓库或本地分支拉取并整合内容 |
| `git push` | 更新远程引用以及相关对象 |

---

## 原始命令分组结构

```text
start a working area
work on the current change
examine the history and state
grow, mark and tweak your common history
collaborate
```

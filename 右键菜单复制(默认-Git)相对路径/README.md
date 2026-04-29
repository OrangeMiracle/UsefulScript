CopyGitPathContextMenu

使用方法
1. 在此文件夹中打开 Windows PowerShell 5.1。
2. 运行：
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
3. 安装普通路径菜单（前两项）：
.\Install-CopyPathContextMenu.ps1
4. 卸载普通路径菜单（前两项）：
.\Rollback-CopyPathContextMenu.ps1
5. 安装 Git 相对路径菜单（后两项）：
.\Install-CopyGitPathContextMenu.ps1
6. 卸载 Git 相对路径菜单（后两项）：
.\Rollback-CopyGitPathContextMenu.ps1

脚本拆分说明
- 普通路径功能与 Git 相对路径功能已经拆分为两套独立安装/卸载脚本
- 两套脚本可单独使用，也可都安装
- 都安装时，菜单按 01/02/03/04 顺序稳定显示

安装时交互选项
1) 是否启用 Git 命令判断仓库根目录（推荐）
- 最准确，可处理普通仓库、worktree、submodule 等
- 需要系统已安装 Git 且 git 在 PATH 中
- 若选择启用但未检测到 Git，不中断安装，自动跳过该方式

2) 是否启用逐级向上查找 .git
- 不依赖 Git 命令
- 不调用 Windows Search，不全盘搜索
- 仅从当前目录向父目录逐层检查固定路径 .git（文件或目录都算）
- 性能开销通常很低，但特殊结构兼容性不如 git rev-parse --show-toplevel


运行时仓库根目录判断顺序
1. 若启用 Git 命令判断：先执行 git -C "工作目录" rev-parse --show-toplevel
2. 若步骤 1 失败且启用了逐级 .git 查找：从工作目录开始逐层向上检查 .git
3. 都失败：复制空字符串，并弹出明确提示

新增菜单项
- 复制文件Git相对路径
- 复制文件所在目录Git相对路径
- 复制文件夹Git相对路径
- 复制文件夹所在目录Git相对路径

菜单顺序（文件右键）
1. 复制当前选择文件路径
2. 复制当前选择文件所在目录路径
3. ────────────────
4. 复制文件Git相对路径
5. 复制文件所在目录Git相对路径

菜单顺序（文件夹右键）
1. 复制当前选择文件夹路径
2. 复制当前选择文件夹所在目录路径
3. ────────────────
4. 复制文件夹Git相对路径
5. 复制文件夹所在目录Git相对路径

说明
- 为了保证顺序稳定，安装脚本会使用有序 Verb 键名（01/02/03/04）
- Git 第一项前会显示分隔线（SeparatorBefore）
- 回滚脚本会分别清理各自功能对应的旧键名与有序键名

路径规则
- 分隔符统一为 /
- 普通相对路径统一输出 ./xxx/yyy
- 仓库根目录本身输出 .
- 文件在仓库根目录下（如 README.md）输出 ./README.md
- 目录模式下若目标目录是仓库根目录，输出 .
- 若目标不在仓库根目录下，运行时报错并复制空字符串

性能与兼容性说明
- 菜单设置 MultiSelectModel=Single，框选多个文件时不触发路径分析
- 兼容 Windows 10 / Windows 11
- 兼容 Windows PowerShell 5.1
- 保留原有复制完整路径、复制所在目录等功能与图标逻辑
- Windows 11 下请在“显示更多选项”中查看经典菜单项

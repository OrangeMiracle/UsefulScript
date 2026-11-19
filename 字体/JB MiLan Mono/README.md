# JB MiLan Mono

用于个人本地编辑器和终端的中英文 TrueType 字族。安装后选择 **JB MiLan Mono**，样式为 **Regular** 和 **Bold**。

| 文件 | 字重 | 大小 |
| --- | ---: | ---: |
| `JBMilanMono-Regular.ttf` | 400 | 8,389,420 字节 |
| `JBMilanMono-Bold.ttf` | 700 | 8,409,284 字节 |

## 来源

| 源文件 | 扫描结果 |
| --- | --- |
| `../JetBrain Mono/JetBrainsMonoNL-Regular.ttf` | JetBrains Mono NL 2.304，静态 TrueType，权重 400，Unicode cmap 含 1,363 个码点 |
| `../JetBrain Mono/JetBrainsMonoNL-Bold.ttf` | JetBrains Mono NL 2.304，静态 TrueType，权重 700，Unicode cmap 含 1,363 个码点 |
| `../小米兰亭Pro/Mi-Lan-Pro-VF.ttf` | MI Lan Pro VF 1.10，可变 TrueType，Unicode cmap 含 28,612 个码点，`wght` 范围 150–700，默认 150 |

两款 NL 文件与同目录 ZIP 中的副本逐字节一致。源目录内另外三款 MiSans、Microsoft Sans Serif 和迷你简细行楷是不同字族。构建仅使用表中三个文件。

## 构建

在本目录运行。Ubuntu 若尚未提供 `venv` 模块，需要先安装发行版的 `python3-venv` 软件包。

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python build.py

# 可选的完整验收。需要 Fontconfig 命令和支持 RAQM 的 Pillow。
.venv/bin/python -m pip install -r requirements-verify.txt
.venv/bin/python verify.py
```

升级时可以用新版本替换相邻目录中的同名源文件，或通过 `build.py --chinese /path/to/source.ttf` 指定新的中文可变 TrueType。英文来源优先使用同名字重的 NL 静态文件，缺少 NL 时使用 `JetBrainsMono-Regular.ttf` 或 `JetBrainsMono-Bold.ttf`。当前构建要求两边为同 UPEM 的 TrueType 轮廓，现有来源均为 1,000 UPEM。

本机已把本次用到的 fontTools 和 HarfBuzz Python 绑定装到 `.deps/`。在当前 Ubuntu 环境可直接运行 `PYTHONPATH="$PWD/.deps" python3 build.py` 或 `PYTHONPATH="$PWD/.deps" python3 verify.py`。验收使用系统已有的 Pillow。

## 合并方式

- 用 fontTools 实例化中文 `wght=400` 和 `wght=700`。源字体把这两个轴坐标命名为 Medium 和 Heavy，成品按所请求的数值命名为 Regular 和 Bold。替换来源的轴范围较窄时，脚本会选用最近的轴端点并打印实际值。
- 此版兰亭的 `gvar` 声明了 28,558 个字形，实际为 28,557 个。脚本校验真实偏移表覆盖全部变体数据，再在内存修正计数。兰亭的 `GPOS` 字偶距会改变网格占宽，而且其字偶类矩阵会使 fontTools 实例化失败。构建在实例化前移除该表，并保留竖排替换与垂直度量。
- JetBrains 提供 ASCII、拉丁文、数字、编程符号及其余保留字符。兰亭提供汉字、注音、CJK 标点与兼容符号、全角形式，以及中文常用的引号、间隔号、破折号和省略号。对子集先确定码点归属，再合并 `glyf`、`hmtx`、`cmap` 和布局表。JetBrains 的 `glyf` 复合引用和 TrueType 提示程序随字体保留。英文 GSUB 移除，中文 GSUB 仅保留竖排特性。
- 英文单元 600，汉字、常用中文标点和全角形式为 1,200（设计单位）。中文使用原始轮廓，通过调整 advance 与水平位置适配网格。中国语文里常见的间隔号和弯引号占一列。宽于一列的 `—`、`―`、`…` 保留两列，以容纳原轮廓。
- 两款字体都使用 1,044 / −300 的水平升部和降部，所有已选中文轮廓均落入这个范围。Windows 裁切度量覆盖全字体的墨迹范围，包括 JetBrains 中刻意跨越行边界的框线。字体按单宽、双宽混合标记，Fontconfig 报告 `spacing=90`（dual-width）。

## 验收

- 每款字体包含 29,140 个 Unicode 码点，JetBrains 贡献 1,353 个，兰亭贡献 27,787 个。按非零 advance 分类有 1,335 个单宽和 27,781 个双宽码点，另有 24 个零宽码点。当前兰亭来源未覆盖补充平面汉字，样例 `𠮷`（U+20BB7）需要其他字体提供。
- 构建后重新解析 TrueType 检查表校验和，逐个比对合并前后子集的映射、轮廓与度量。验收再次核对全部可打印 ASCII 与原始 JetBrains、Latin/CJK 字重差异、中文竖排替换及 13 组 HarfBuzz 运算符测试。显式启用常用连字特性时，`!=`、`==`、`=>`、`>=`、`<=`、`===` 等仍逐字符输出。
- `fc-scan`、`fc-list`、`fc-match` 在临时 Fontconfig 目录中识别同一字族的两个样式。FreeType/RAQM 在 12、14、16、20、24 px 检查混排网格。可用 [specimen.txt](specimen.txt) 在自己的编辑器里复测，[specimen.png](specimen.png) 是两种字重的实际渲染。
- 终端自己决定 Unicode 列宽。在本机 `C.UTF-8` 下，`wcwidth` 给 `—`、`―`、`…` 各分配一列，与字体的两列占宽不同。常用汉字与全角标点的列宽匹配。仅列出单宽字体的终端选择器可能需要手动输入字族名。

## Ubuntu 用户级安装和卸载

从成品目录安装，随后重新打开应用并选择 **JB MiLan Mono**。

```bash
font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JB MiLan Mono"
install -d "$font_dir"
install -m 0644 JBMilanMono-Regular.ttf JBMilanMono-Bold.ttf "$font_dir/"
fc-cache -f "$font_dir"
fc-list 'JB MiLan Mono' family style file
fc-match 'JB MiLan Mono:style=Regular'
fc-match 'JB MiLan Mono:style=Bold'
```

卸载时移除上述两款字体并刷新缓存。

```bash
font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JB MiLan Mono"
rm -f -- "$font_dir/JBMilanMono-Regular.ttf" "$font_dir/JBMilanMono-Bold.ttf"
fc-cache -f
```

## 来源授权

- JetBrains Mono 采用 SIL Open Font License 1.1。[OFL-JetBrainsMono.txt](OFL-JetBrainsMono.txt) 是随源 ZIP 提供的原文，成品保留源字体版权信息。 [JetBrains Mono 项目](https://github.com/JetBrains/JetBrainsMono)
- 小米兰亭 Pro 源字体署名为 `Copyright(c) Beijing Founder Electronics Co.,Ltd.2019`，其内嵌 name 表未提供许可正文或许可链接。成品保留该版权信息及源 `fsType=0x0008` 嵌入标记。此处未核实兰亭 Pro 的修改或分发许可，成品按项目要求仅用于个人本地测试。小米的 MiSans 授权适用于另一个字族。 [小米字体项目历史](https://hyperos.mi.com/font/zh/about/)

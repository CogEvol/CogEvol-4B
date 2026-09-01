# CogEvol-4B — 端侧学习环境生成模型

**一个 4B 后训练模型：输入一句话课程需求，单次前向直接产出完整学习工件 —— 结构化 slide JSON 与自包含可交互 HTML —— 笔记本本地、全程断网可跑。**

<p align="center">
  <a href="https://arxiv.org/abs/2608.30968"><img src="https://img.shields.io/badge/arXiv-2608.30968-b31b1b?style=flat-square" alt="arXiv:2608.30968"/></a>
  <a href="https://huggingface.co/CogEvol/CogEvol-4B"><img src="https://img.shields.io/badge/%F0%9F%A4%97_HF-Weights_(BF16)-FFD21E?style=flat-square" alt="HF weights"/></a>
  <a href="https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF"><img src="https://img.shields.io/badge/%F0%9F%A4%97_HF-GGUF_(Q4__K__M)-FFD21E?style=flat-square" alt="HF GGUF"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Code_MIT-green?style=flat-square" alt="License: code MIT"/></a>
  <a href="#12-许可与引用"><img src="https://img.shields.io/badge/Weights_License-Apache--2.0-blue?style=flat-square" alt="Weights: Apache 2.0"/></a>
  <br/>
  <img src="https://img.shields.io/badge/llama.cpp-0.3.0%2B-black?style=flat-square" alt="llama.cpp"/>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20CUDA-lightgrey?style=flat-square" alt="platforms"/>
  <img src="https://img.shields.io/badge/Qwen3.5--4B-hybrid_arch-6E40C9?style=flat-square" alt="Qwen3.5-4B"/>
</p>

- 🧠 基座 Qwen3.5-4B 混合架构（48 层 GDN 线性注意力 + 16 层全注意力）→ mix SFT（53,687 条生产验证样本）→ slide RL → HTML RL
- 📦 单文件量化：**Q4_K_M GGUF，2.4 GB** —— Apple Silicon / CUDA / 纯 CPU 皆可通过 llama.cpp 运行
- ⚡ **MacBook Pro M2 Pro（16 GB）实测：生成 ~33 tok/s、prefill ~470 tok/s** —— 约 6 分钟生成一门完整互动课程，无需 GPU 集群、无需 API Key
- 🔌 **推理零外部依赖**：模型、应用、静态资源全部本地。下文的演示流程是在关闭 WiFi 的状态下录制的
- 🎓 与 [OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) 开箱即用（`.env.local` 配本地 provider 即可），另附补丁增加运行时 brief 扩写器与全程断网渲染（见第 7 节）

| 模型 | 链接 | 协议 |
|---|---|---|
| **CogEvol-4B**（BF16 safetensors） | <https://huggingface.co/CogEvol/CogEvol-4B> | Apache 2.0 |
| **CogEvol-4B Q4_K_M GGUF**（2.4 GB，llama.cpp） | <https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF> | Apache 2.0 |

> 本仓库**只包含代码**：部署脚本、OpenMAIC 集成补丁、评测工具。权重在 HuggingFace。

[English README](README.md)

---

## 目录

1. [CogEvol-4B 能做什么](#1-cogevol-4b-能做什么)
2. [仓库结构](#2-仓库结构)
3. [环境要求](#3-环境要求)
4. [第一步 — 下载模型](#4-第一步--下载模型)
5. [第二步 — 编译 llama.cpp](#5-第二步--编译-llamacpp)
6. [第三步 — 启动推理服务](#6-第三步--启动推理服务)
7. [第四步 — 跑通 OpenMAIC 应用](#7-第四步--跑通-openmaic-应用)
8. [第五步 — 全程断网演示](#8-第五步--全程断网演示)
9. [评测](#9-评测)
10. [技术说明](#10-技术说明)
11. [问题排查](#11-问题排查)
12. [许可与引用](#12-许可与引用)

---

## 1. CogEvol-4B 能做什么

输入一段自由格式的需求，比如 ——

> 用互动模拟教我单摆运动，包含可调节摆长和重力的实验

—— 模型在**单次前向**（无 agent 循环）内产出：

| 模态 | 输出 | 说明 |
|---|---|---|
| **Slide** | 16:9 场景图 **JSON**（1000×562 画布；text / shape / line / image / table / chart / LaTeX / video 八类元素 + background） | JSON 是**渲染契约**：生产渲染器对非法字段、字符串坐标、未知元素类型直接硬失败 |
| **互动 HTML** | **自包含** HTML 页面（simulation / diagram / code / game / 3D 五类组件），在 iframe 中渲染 | 带滑杆与预设的物理模拟、流程图、编程练习、教学游戏 |

在 OpenMAIC 应用里，一句话课程需求会扩展成完整多场景课堂：slide、互动场景、测验、教师脚本（逐场景 action 列表）、多智能体课堂对话 —— 全部由这一个 4B 模型生成。

Q4_K_M 与 BF16 在同一条 brief、temperature 0 下的 slide 输出（生产渲染器渲染；更多对照见 [GGUF 仓库](https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF)）：

| BF16（服务器） | Q4_K_M（端侧） |
|---|---|
| <img src="assets/examples/slide_hq3_002_bf16.png" width="420" alt="BF16 slide 渲染"/> | <img src="assets/examples/slide_hq3_002_q4.png" width="420" alt="Q4_K_M slide 渲染"/> |

### 参考设备实测（M2 Pro / 16 GB / macOS 13.3 / Metal）

| 工作负载 | 结果 |
|---|---|
| Slide 模态，20 条 brief | **20/20 JSON 契约通过**，平均 **34.8 tok/s**，平均 **63.4 s** / 张 |
| HTML 模态，内部 500 条评测集抽查 20 条（simulation/diagram/code/game） | **20/20 有效 HTML**，确定性浏览器探针 0 运行时错误 / 0 布局溢出，声明的控件全部可点 |
| Prefill（长课程 prompt，约 4k token） | ~450–500 tok/s |
| 纯 CPU 回退（`-ngl 0`，笔记本级设备） | ~18–24 tok/s —— 能跑，只是慢 |

### 纯 CPU 笔记本实测（M1 Pro / 16 GB / macOS 13.2 / `serve.sh` 自动 CPU 回退）

同一组服务参数 —— 该机器上 Metal 不可用，llama.cpp 跑 CPU。原始服务速度 + OpenMAIC
应用内生成一门课的端到端耗时：

| 工作负载 | 结果 |
|---|---|
| 服务原始速度 | prefill ~30–45 tok/s · 生成 ~6–12 tok/s（上下文越长越慢） |
| 课程大纲 + Agent 人设 | ~2.5 分钟 |
| 应用内一页 **slide** | ~7 分钟（brief 扩写 ~30 s + slide JSON ~4–5 分钟 + 教师动作 ~2 分钟） |
| 应用内一页**互动页** | ~12–20 分钟（HTML 输出比 slide JSON 长数倍） |

两个 CPU 特有效应值得知道（详见第 10 节）：应用的页面 prompt 自带 ~10k token 的生产
模板，冷服务首次 prefill 约 5 分钟 —— 同一 server 进程内，后续调用会命中 llama-server
的前缀缓存而跳过它；另外单次应用内调用可能超过 Node 默认的 5 分钟 fetch 超时，补丁已
修复（第 7 节路径 B）。

## 2. 仓库结构

```
CogEvol-4B/
├── README.md / README_zh.md
├── LICENSE                        # MIT（本仓库代码）
├── CITATION.cff                   # GitHub「Cite this repository」
├── scripts/
│   ├── serve.sh                   # 用验证过的参数启动 llama-server
│   ├── apply-openmaic-patch.sh    # 给 OpenMAIC 检出目录打补丁 + 写 .env.local
│   └── fetch-offline-assets.sh    # 本地化 katex/tailwind/codemirror（断网渲染用）
├── patches/
│   ├── openmaic/
│   │   └── openmaic-offline-on-device.patch     # brief 扩写器 + 断网组件 + 长调用超时修复（对公开 main，11 个文件）
│   └── llama-cpp/
│       └── macos13-metal-buffer-fix.md             # GGML_ASSERT(buf_dst) 崩溃修复
├── eval/
│   ├── slide_eval.py              # slide JSON 契约评测
│   ├── html_eval.py               # 互动 HTML 评测
│   └── samples/                   # 3 条 slide brief + 3 条 HTML case，拿来即测
├── assets/examples/               # BF16 与 Q4_K_M 渲染对照
└── .github/                       # CI、issue 与 PR 模板
```

## 3. 环境要求

| | |
|---|---|
| 硬件 | 任意 Apple Silicon Mac（实测 M2 Pro / 16 GB），或带 CUDA 的 Linux 机器，或纯 CPU（较慢）。约 8 GB 空闲磁盘 |
| 系统 | macOS 13+（实测 13.2–13.3；≤13.x 请先看 llama.cpp 补丁说明）或 Linux |
| 工具 | `git`、C/C++ 工具链（Xcode 命令行工具 / build-essential）、`cmake ≥ 3.14`、`python3 ≥ 3.9`（评测脚本零第三方依赖） |
| 应用侧 | Node.js ≥ 20 与 `pnpm`（`corepack enable`），以及 [OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) 仓库（AGPL-3.0） |

```bash
# macOS
xcode-select --install
brew install cmake git python@3.12 || true
corepack enable                      # 提供 pnpm

# Linux（Debian/Ubuntu）
sudo apt install -y build-essential cmake git python3 python3-pip
corepack enable
```

## 4. 第一步 — 下载模型

下载 Q4_K_M GGUF（2.4 GB）：

```bash
# huggingface CLI
pip install -U "huggingface_hub[cli]"
hf download CogEvol/CogEvol-4B-Q4_K_M-GGUF cogevol-4b-q4_k_m.gguf --local-dir .

# 或直接 https
curl -L -o cogevol-4b-q4_k_m.gguf \
  "https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF/resolve/main/cogevol-4b-q4_k_m.gguf"
```

校验完整性：

```bash
shasum -a 256 cogevol-4b-q4_k_m.gguf
# 期望值: 9bd86e6e7324d7004d3d7a8c36dadc8a053add075a1d39b5fbfb4b8ff754ec2b
```

> **想自己重量化？** 用 llama.cpp 的 `convert_hf_to_gguf.py --no-mtp` 转换
> [CogEvol/CogEvol-4B](https://huggingface.co/CogEvol/CogEvol-4B)（BF16）。
> `--no-mtp` 必须带：RL 导出已剥离 MTP 头，带上会在运行时报
> `blk.32.attn_norm` 缺失。GGUF 元数据应为 `arch=qwen35, block_count=32,
> full_attention_interval=4`，且没有 `nextn` 键。

## 5. 第二步 — 编译 llama.cpp

CogEvol-4B 依赖 llama.cpp 对 Qwen3.5 混合架构的支持以及 `--jinja`。近期的 master
版本均可；源码编译约 5 分钟：

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build
cmake --build build --config Release -j
# 产物在 build/bin/ ；可选：
sudo cp build/bin/llama-server /usr/local/bin/    # 或把 build/bin 加进 PATH
```

**旧版 macOS（≤ 13.x）的两个坑** —— 开发时都踩过，都已解决：

1. **官方预编译二进制加载失败**（`dyld` 报 `minos` / 缺 `_MTLResidencySetDescriptor`）。
   像上面这样用本地 SDK 源码编译即可规避。
2. **Metal 崩溃 `GGML_ASSERT(buf_dst)`**：旧 macOS 的 Metal 驱动对非页对齐（含零长度）
   的 `newBufferWithBytesNoCopy` 包装返回 `nil`。如果遇到，按
   [`patches/llama-cpp/macos13-metal-buffer-fix.md`](patches/llama-cpp/macos13-metal-buffer-fix.md)
   替换 `ggml-metal-context.m` 中的一个函数后重新编译。macOS ≥ 14 大概率不需要。

**小模型冒烟测试**（热缓存下模型约 3 秒加载完）：

```bash
./scripts/serve.sh /path/to/cogevol-4b-q4_k_m.gguf   # 另开一个终端：
curl --noproxy '*' http://127.0.0.1:8081/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"用一句话介绍什么是肘关节"}]}'
```

## 6. 第三步 — 启动推理服务

`scripts/serve.sh` 以本 README 所有数字使用的精确参数启动 OpenAI 兼容服务（GPU
优先，自动回退 CPU）：

```bash
./scripts/serve.sh /path/to/cogevol-4b-q4_k_m.gguf [端口]   # 默认 8081
```

其核心命令：

```bash
llama-server -m cogevol-4b-q4_k_m.gguf --port 8081 \
  -c 32768 -ngl 99 --temp 0 -fa auto \
  --jinja --chat-template-kwargs '{"enable_thinking": false}'
```

| 参数 | 原因 |
|---|---|
| `-c 32768` | 课程生成的 prompt 可达 ~4k token、互动 HTML 输出可达 ~19k 字符；32768 是验证过的余量（下限 24576） |
| `-ngl 99` | 全部层卸载到 GPU（Metal/CUDA）；脚本会自动回退 `-ngl 0`（GPU 启动崩溃时立即回退，不等超时） |
| `--temp 0` | 确定性输出 —— 与本 README 所有公开数字一致 |
| `-fa auto` | Flash Attention |
| `--jinja` | 启用聊天模板 kwargs 与工具式处理；**下面那个参数依赖它** |
| `--chat-template-kwargs '{"enable_thinking": false}'` | **必须。** 否则 Qwen3.5 式思考会先吃光全部 token 预算。逐请求传 `"chat_template_kwargs": {"enable_thinking": false}` 也行 —— 服务端写死更保险 |

健康检查注意：加载中 `/health` 返回 **503，就绪才是 200** —— 务必判断精确状态码
（curl 不带 `--fail` 时 503 的退出码也是 0，坑过不止一个启动脚本）。

## 7. 第四步 — 跑通 OpenMAIC 应用

[OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) 是该模型训练所配套的多智能体互动
课堂应用。用 CogEvol-4B 驱动它有两条路：

### 路径 A —— 原版 OpenMAIC，免补丁（适用当前公开 `main`）

应用内置免 Key 的 Ollama 兼容 provider：配两个环境变量，所有大模型调用都指向
你的本地 llama-server。

```bash
git clone https://github.com/THU-MAIC/OpenMAIC && cd OpenMAIC

cp .env.example .env.local
cat >> .env.local <<'EOF'
OLLAMA_BASE_URL=http://127.0.0.1:8081/v1
OLLAMA_MODELS=cogevol-4b-q4_k_m
EOF

pnpm install
pnpm build
pnpm start          # http://localhost:3000
```

在应用里从模型选择器选 `cogevol-4b-q4_k_m`（没配任何云厂商 Key 时它是唯一
provider），输入课程需求（如 `用互动模拟教我单摆运动，包含可调节摆长和重力的实验`），
进入课堂即可。

### 路径 B —— 端侧补丁（brief 扩写器 + 断网组件渲染）

原版应用直接用大纲的**简短条目**（标题 + 一两句描述）生成每页。我们的补丁基于公开
OpenMAIC commit `f6cf8fd4`（2026-08-30）验证，上游自己的测试套件保持全绿
（`packages/@openmaic/generation` 136/136）：

1. **新增运行时 brief 扩写器**（`page-brief-expander` prompt）：在 slide / 组件生成
   之前，把简短条目先扩写成详实、以内容为先的 brief。这是 4B 模型在该应用里最大的
   质量杠杆，与我们训练 / 评测数据的 brief 写法对齐。扩写是**选择性开启**的：只有
   route 提供课程上下文时才运行（打过补丁的 `scene-content` route 一直提供），包的
   其他使用方行为不变；
2. **让生成的互动组件断网可渲染**：KaTeX 改由应用自身同源提供，模型输出的
   Tailwind / CodeMirror CDN 引用重写到本地镜像，其余外链一律剥离（见第 8 节）；
3. **解除 Node 默认的 5 分钟 fetch 超时**（新增 `instrumentation.ts`）：CPU 级设备上
   应用内单页调用要跑 5–15 分钟，原生 undici 会以 `Headers Timeout Error` 掐断 ——
   之后应用还会无限重试、永远失败。补丁注册了一个不带 header/body 超时的全局
   undici dispatcher（这里安全：应用只会访问 `127.0.0.1`）。

```bash
git clone https://github.com/THU-MAIC/OpenMAIC && cd OpenMAIC
git checkout f6cf8fd4                   # 补丁验证所基于的 commit

/path/to/CogEvol-4B/scripts/apply-openmaic-patch.sh .   # 打补丁 + 写 .env.local
/path/to/CogEvol-4B/scripts/fetch-offline-assets.sh .   # katex/tailwind/codemirror → public/

pnpm install
pnpm build
pnpm start -p 3200         # http://localhost:3200
```

> **为什么不带 `--`？** pnpm 会把 `--` 原样转发给 `next start`，后者把 `-p` 解析成
> 目录名（报 `Invalid project directory .../-p`）。pnpm 本身不需要 `--` 就能透传参数。

> **上游更新之后。** 补丁涉及 11 个文件、以新增为主；若更新的 OpenMAIC commit 已
> 漂移，`apply-openmaic-patch.sh` 会先 dry-run 并明确报错。要么钉在 `f6cf8fd4`，
> 要么手工重放补丁 —— CI 每次推送都会对钉定基线复检，补丁漂移会响亮失败而不是
> 静默失效。

### 两条路都会看到

1. 模型选择器里只有一个本地模型 `cogevol-4b-q4_k_m`；
2. 大纲 → 逐页生成 → 课堂打开（M2 Pro 每页约 3–6 分钟；纯 CPU 笔记本一页 slide 约
   7 分钟、一页互动页约 12–20 分钟 —— 见第 1 节 CPU 表）。互动场景在 iframe 中渲染 ——
   滑杆、预设、启动/暂停/重置全部可用。

## 8. 第五步 — 全程断网演示

完成第 6、7 节（路径 B）后，以下流程**关掉 WiFi 也能跑** —— 这正是录制端侧演示用的流程：

1. `scripts/serve.sh` —— 模型加载，`/health` 返回 200；
2. `pnpm start` —— 应用启动（确认 `.env.local` 里没有云厂商 Key；应用补丁脚本写的是干净的）；
3. 生成一门课程，打开互动场景；
4. 关 WiFi → 再生成一门 → 依然全流程可用，样式和 LaTeX 公式都在。

为什么必须打补丁：生成的互动页习惯性引用 `https://cdn.tailwindcss.com`（模型输出的
运行时 CSS 编译器），应用自身也会注入 jsDelivr 的 KaTeX。断网时两者皆挂 —— 页面裸
奔、公式变成 `\(T = 2\pi\sqrt{L/g}\)` 原码。打过补丁的后处理器会把这三个 CDN 重写
到 `public/` 下的同源路径（由 `fetch-offline-assets.sh` 安装），其余外链直接剥离。

**已知的断网降级**（设计为优雅降级）：`code` 组件没有 Pyodide 无法**执行** Python
（编辑器和高亮仍在 —— 外链脚本是被剥离而不是挂起）；`visualization3d` 组件失去
three.js。simulation、diagram、game、slide、quiz 五类断网 100% 可用。若需要，按同一
后处理模式把这两个运行时也做本地镜像即可。

## 9. 评测

两个脚本复现公开评测的设置：都打本地服务、都关思考、都确定性（`temperature 0`）。
Python ≥ 3.9，零第三方依赖。

**Slide 契约**（JSON 必须可解析且含 `elements` 与 `background`）：

```bash
cd eval
python3 slide_eval.py --port 8081 --data samples/slide_briefs_sample.jsonl --out out_slide
```

**互动 HTML**（从回复中抽取 HTML 页面；system prompt 从你的 OpenMAIC 检出目录解析 ——
直接传仓库根目录即可，旧版 `lib/prompts/templates` 与新版
`packages/@openmaic/generation/templates` 两种布局都支持）：

```bash
python3 html_eval.py --port 8081 \
  --templates /path/to/OpenMAIC \
  --data samples/html_cases_sample.jsonl --out out_html
```

产出的 `.html` 直接用浏览器打开即可。参考结果（M2 Pro）：slide 20/20 契约通过、
平均 34.8 tok/s、平均 63.4 s/张；HTML 20/20 抽取成功（内部 500 条评测集中分层抽
10 条 + simulation 10 条），全部通过确定性无头浏览器探针（无运行时错误、无布局
溢出、声明的控件全部可点击）。

## 10. 技术说明

- **架构**：Qwen3.5-4B 混合 —— 48 层 GDN（线性注意力）+ 16 层全注意力，
  `full_attention_interval=4`，共 32 个 block。当前 llama.cpp 已支持。
- **思考必须关闭**（见第 6 节参数表）。实测只给 `--reasoning-budget 0` 时自定义
  聊天模板仍会输出 ~260 个思考 token；`--chat-template-kwargs
  '{"enable_thinking": false}'` 才是可靠开关。
- **Q4_K_M token 膨胀**：同一条 brief，量化版输出比 BF16 长 ~10–20%。仍满足契约，
  但 `max_tokens` 要给够。
- **Token 预算**：slide → 8192；互动 HTML → 16384 且上下文 ≥ 24576（一个内容丰富的
  模拟页可达 ~19k 字符 ≈ 5k token）。
- **应用内的页面 prompt 很大**：生产模板让每次 scene-content 调用带上 ~9–10k token，
  而评测 brief 只有 ~200 token。CPU 上冷服务首次 prefill 约 5 分钟；此后同一 server
  进程内的调用会命中 llama-server 的 prompt 前缀缓存、跳过共享前缀 —— 所以第二门课
  明显快于第一门，重启 `llama-server` 即复位。
- **生成速度随上下文变长而下降**：M1 Pro CPU 实测短上下文 ~12 tok/s，槽位累积到
  ~11k token 后掉到 ~6 tok/s。一节课越往后越慢。
- **fetch 超时**：Node 的 undici 默认在 5 分钟内等不到响应头就断开 —— 比应用内许多
  CPU 调用更短，而且应用会无限重试这条注定失败的调用。OpenMAIC 补丁（第 7 节路径 B）
  通过 `instrumentation.ts` 里的全局 dispatcher 解除了它；如果你维护 fork，请保留。
- **后训练脉络**：mix SFT → slide RL → HTML RL；RL 终版 ckpt `html-4b-rl-v5-step249`；
  导出时已剥离 MTP 头（转换带 `--no-mtp`）。
- **代理**：如果你跑着本地 HTTP 代理（Clash 等），它会劫持 `127.0.0.1` 的请求，
  把"服务已死"伪装成它自己的 502/503。本仓库所有脚本都设了
  `no_proxy=127.0.0.1,localhost`；自己写脚本时记得保留。

## 11. 问题排查

| 症状 | 解决 |
|---|---|
| 启动即 `GGML_ASSERT(buf_dst)`（macOS ≤ 13） | `serve.sh` 会自动回退 CPU；要满速 GPU 请应用 [`patches/llama-cpp/macos13-metal-buffer-fix.md`](patches/llama-cpp/macos13-metal-buffer-fix.md) 后重编译 |
| llama.cpp 预编译版 dyld 报错（`minos`、`_MTLResidencySetDescriptor`） | 源码编译（第 5 节）—— 预编译 targeting 新版 macOS SDK |
| 模型一直输出思考 / 内容为空 | 用 `--jinja --chat-template-kwargs '{"enable_thinking": false}'` 启动（第 6 节） |
| 加载时报缺 `blk.32.attn_norm` | GGUF 转换时没带 `--no-mtp` —— 重新量化（第 4 节） |
| HTML 生成到一半被截断 | 调大 `-c`（≥ 24576），请求 `max_tokens` 16384 |
| 页面生成报 `Headers Timeout Error`、应用无限重试 | 调用超过了 undici 默认 5 分钟超时 —— 应用补丁（第 7 节路径 B 已含 `instrumentation.ts` 修复）后重新 build |
| `next start` 报 `Invalid project directory .../-p` | 用了 `pnpm start -- -p 3200`；pnpm 会把 `--` 原样透传 —— 改用 `pnpm start -p 3200`（第 7 节） |
| 应用里出现云厂商供应商 / 走了网络 | `.env.local` 缺 `OLLAMA_*` 配置（第 7 节路径 A）；确认没配云厂商 Key |
| 组件无样式、屏幕上出现 `\( ... \)` 原码 | 断网资源未安装 → 跑 `fetch-offline-assets.sh`，重新 build 应用 |
| `apply-openmaic-patch.sh` 报漂移 | 检出比验证基线新 —— 钉在 `f6cf8fd4` 或手工重放补丁（第 7 节路径 B） |
| 对 127.0.0.1 的请求莫名 502 | 本地代理劫持 —— `export no_proxy=127.0.0.1,localhost` |
| 服务"起来了"但生成迟迟不开始 | `/health` 返回的是 503 不是 200 —— 按精确状态码轮询 |

## 12. 许可与引用

- **本仓库**（脚本、补丁、评测工具）：MIT —— 见 [LICENSE](LICENSE)。
- **模型权重**：[CogEvol-4B](https://huggingface.co/CogEvol/CogEvol-4B) 与
  [CogEvol-4B-Q4_K_M-GGUF](https://huggingface.co/CogEvol/CogEvol-4B-Q4_K_M-GGUF)
  以 **Apache 2.0** 协议开源。
- **OpenMAIC 补丁**修改的是 AGPL-3.0 代码；结合作品继承 AGPL-3.0。

如果 CogEvol-4B 对你有用，欢迎引用技术报告
（[arXiv:2608.30968](https://arxiv.org/abs/2608.30968)）：

```bibtex
@misc{tu2026cogevolefficientreliablelearning,
      title={CogEvol: Towards Efficient and Reliable Learning Environment Generation},
      author={Shangqing Tu and Daniel Zhang-Li and Yucheng Wang and Shiyu Gan and Yanpeng Wang and Huiqiang Rong and Mofei Chen and Shen Yang and Yini Chen and Yinuo Duan and Haoxuan Li and Binglin Liu and Ye He and Danqi Zheng and Zhanxin Hao and Yuxuan Wu and Mengting Tao and Yuqiu Liu and Jifan Yu and Juanzi Li and Bin Xu and Lei Hou and Huiqin Liu and Yu Zhang},
      year={2026},
      eprint={2608.30968},
      archivePrefix={arXiv},
      primaryClass={cs.CL},
      url={https://arxiv.org/abs/2608.30968}
}
```

基于 [llama.cpp](https://github.com/ggml-org/llama.cpp)、[Qwen](https://github.com/QwenLM) 与 [OpenMAIC](https://github.com/THU-MAIC/OpenMAIC) 构建 —— 一并致谢。

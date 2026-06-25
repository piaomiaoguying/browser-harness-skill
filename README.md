# 🧠 browser-harness Skill

> **一行命令，让 Claude 直接控制你的 Chrome。**
> 不是 Selenium，不是 Playwright，不是 Puppeteer —— 是一根直连 Chrome CDP 的超薄导线，零中间商。

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-6B4FBB?logo=anthropic&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)

---

## 它能做什么？

```
你: 帮我打开小红书，搜索"露营装备"，把前10条笔记标题和点赞数抓下来

Claude: *连接 Chrome → 打开小红书 → 输入搜索 → 滚动加载 → 提取数据 → 整理表格*
        全程不到 60 秒，你的浏览器你全程看着。
```

- 🛒 **电商比价** — 跨平台抓取商品价格、评论、销量
- 📊 **数据采集** — 任意网页结构化提取，支持分页/无限滚动
- 📝 **表单自动填** — 批量填写、提交、导出
- 🔐 **登录态复用** — 用你自己的 Chrome，cookie/session 全自动继承
- 🎮 **Canvas/PWA 应用** — 飞书、Figma 等虚拟渲染页面也能搞

---

## 30 秒上手

### 1. 安装 CLI

```bash
uv tool install --python 3.12 --upgrade --force browser-harness
```

### 2. 注册 Skill

```bash
browser-harness skill
```

### 3. 打开 Chrome 远程调试

在 Chrome 地址栏输入：

```
chrome://inspect/#remote-debugging
```

勾选 **Allow remote debugging**，Chrome 144+ 首次连接时点 Allow。

### 4. 试一下

在 Claude Code 里随便说一句话：

> "帮我打开 GitHub trending 页面，把今天的热门项目名和 star 数抓下来"

搞定。

---

## 工作原理

```
你的指令
   │
   ▼
Claude Code（读取 SKILL.md，生成 Python 脚本）
   │
   ▼
browser-harness CLI（一行命令执行脚本）
   │
   ▼
Chrome DevTools Protocol（直连 Chrome）
   │
   ▼
你正在看的浏览器 ← 就是这个，不是无头浏览器
```

**没有 WebDriver，没有浏览器驱动，没有 headless Chrome。**
一根 WebSocket 直连你正在运行的 Chrome，你的登录态、扩展、设置全部继承。

---

## 为什么不是 Playwright / Selenium / Agent Browser？

| | browser-harness | Playwright | Selenium | Agent Browser |
|---|---|---|---|---|
| **连接方式** | CDP 直连真实 Chrome | 自带浏览器 | WebDriver | 自带/模拟浏览器 |
| **反爬检测** | ✅ **几乎不可能被拦** — 你用的就是真实浏览器 | ❌ `navigator.webdriver=true`，特征明显 | ❌ WebDriver 协议特征明显 | ❌ 自动化浏览器指纹可识别 |
| **复用登录态** | ✅ 自动继承 | ❌ 需手动注入 | ❌ 需手动注入 | ❌ 需手动注入 |
| **Chrome 扩展** | ✅ 全部可用 | ❌ | ❌ | ❌ |
| **Canvas/PWA** | ✅ CDP 原生事件 | ⚠️ 有限 | ❌ | ⚠️ 有限 |
| **安装体积** | ~2MB | ~300MB | ~150MB | ~200MB+ |
| **启动速度** | 秒连（复用已有 Chrome） | 需启动新实例 | 需启动新实例 | 需启动新实例 |
| **AI 原生** | ✅ Claude Code 原生 Skill | ❌ | ❌ | ⚠️ 部分支持 |

### 为什么反爬拦不住？

Playwright、Selenium、Agent Browser 启动的是**自动化浏览器实例** — 它们会在 `navigator.webdriver`、Chrome DevTools Protocol 检测、UA 指纹、CDP Runtime domain 注入等方面留下明显特征。网站只需几行 JS 就能识别：

```js
// 反爬检测（Playwright/Selenium 会暴露）
if (navigator.webdriver === true) return block();
if (window.chrome?.runtime?.id === undefined) return block();
```

**browser-harness 连的是你日常使用的 Chrome** — 你的登录态、扩展、历史记录、指纹全都是"真人"特征。对网站来说，这和你自己手动操作没有任何区别。

> 🛒 **实际效果**：淘宝、京东、小红书、LinkedIn 等对自动化浏览器严格拦截的平台，browser-harness 可以正常访问，不白屏、不弹验证码。

---

## 比官方 Skill 强在哪？

官方 [`SKILL.md`](https://github.com/browser-use/browser-harness/blob/main/SKILL.md) 只有 ~120 行基础用法。本项目将其重写为**模块化的实战知识体系**：

| 维度 | 官方 Skill | 本项目 Skill |
|---|---|---|
| **平台覆盖** | 仅 macOS/Linux heredoc | ✅ 完整 Windows/PowerShell 方案 + 故障降级流程 |
| **标签页管理** | 一句话带过 | ✅ 详解 `switch_tab()` 三步原理，防止 session 绑定错位 |
| **`js()` 调试** | 无 | ✅ IIFE 写法规范 + 返回值异常三板斧排查表 |
| **Canvas/PWA** | 无 | ✅ 虚拟渲染检测 + 内存数据提取（PWA 缓存 / Redux store / React fiber）+ 滚动提取 pipeline |
| **CDP 底层参考** | 无 | ✅ Input/Runtime/Network/DOM 完整代码示例 |
| **数据提取策略** | 无 | ✅ 5 级优先级：js() → page_info → CDP 滚动 → 网络拦截 → 截图 |
| **daemon 清理** | 无 | ✅ 任务结束检查清单 + 跨平台清理命令 |
| **架构** | 单文件 120 行 | ✅ 核心 110 行 + 5 个按需加载指南，遇到复杂场景自动深入 |

**一句话：官方 Skill 告诉你"能做什么"，本项目 Skill 告诉你"怎么不踩坑"。**

---

## 高级玩法

### 跨 iframe / Shadow DOM 点击

CDP 坐标级鼠标事件，穿透一切 DOM 边界：

```python
click_at_xy(500, 300)  # 精准点击，不管它在哪层嵌套里
```

### 网络请求拦截

```python
cdp("Network.enable")
events = drain_events()  # 抓取所有网络请求/响应
```

### 虚拟列表滚动

飞书文档、Google Sheets 这种 Canvas 渲染的虚拟列表，普通 JS 滚动无效，CDP 原生事件直接驱动：

```python
scroll(500, 400, dy=-300)  # CDP 级原生滚轮事件
```

### 多标签页管理

```python
tabs = list_tabs()           # 列出所有标签页
new_tab("https://...")       # 新建并自动切换
switch_tab(target)           # 切换到指定标签页
close_tab(target)            # 关闭标签页
```

---

## 常见问题

<details>
<summary><b>首次执行为什么那么慢？</b></summary>
首次连接需要启动 daemon + CDP 握手，大约 30~60 秒，这是正常的。后续调用秒连。
</details>

<details>
<summary><b>PowerShell 不支持 heredoc？</b></summary>
Windows 下多行脚本写文件再用 <code>Get-Content</code> pipe：

```powershell
Set-Content script.py -Value "print(page_info())"
Get-Content script.py | browser-harness
```
</details>

<details>
<summary><b>会不会看到我的密码？</b></summary>
Skill 运行在你本地，连的是你自己的 Chrome，数据不经过任何第三方服务器。你的浏览器你做主。
</details>

---

## Skill 架构：按需加载，不浪费上下文

```
skills/browser-harness/
├── SKILL.md                          ← 核心（110 行，始终加载）
│   ├── 使用方式 / 连接 / daemon 管理
│   ├── Page Workflow 5 步
│   ├── 数据提取策略优先级
│   ├── Top 5 高频 Gotchas
│   └── 📖 按需加载路由表（"遇到 X → 去读 Y"）
│
└── guides/                           ← 按需加载（遇到对应场景才读）
    ├── virtual-rendering.md          虚拟渲染检测 + 应对策略
    ├── scroll-discovery.md           滚动容器发现 + 内容提取 pipeline
    ├── memory-extraction.md          PWA 缓存 / Redux / React fiber 提取
    ├── cdp-reference.md              CDP 底层 API 参考
    └── debugging.md                  js() 调试 + 管道故障诊断
```

**效果**：简单任务只加载 5 KB（省 72%），复杂场景按需叠加 2~5 KB 的专项指南。

---

## 完整文档

- 📖 [Skill 核心](skills/browser-harness/SKILL.md) — 使用方式、工作流、提取策略、路由表
- 🎭 [虚拟渲染指南](skills/browser-harness/guides/virtual-rendering.md) — Canvas/虚拟列表检测与应对
- 📜 [滚动提取指南](skills/browser-harness/guides/scroll-discovery.md) — 滚动容器发现 + 逐帧提取 pipeline
- 🧠 [内存提取指南](skills/browser-harness/guides/memory-extraction.md) — PWA 缓存 / Redux store / React fiber
- ⚡ [CDP 参考](skills/browser-harness/guides/cdp-reference.md) — Input/Runtime/Network/DOM 底层 API
- 🔧 [调试指南](skills/browser-harness/guides/debugging.md) — js() 异常排查 + 管道故障诊断
- 📋 [安装指南](skills/browser-harness/references/install.md) — 详细安装步骤和故障排查


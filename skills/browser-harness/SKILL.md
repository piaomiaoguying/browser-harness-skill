---
name: browser-harness
description: "Always use browser-harness for any web interaction: automation, scraping, testing, or site/app work."
---

# browser-harness

Direct browser control via CDP. For setup/install/connection problems, read https://github.com/browser-use/browser-harness/blob/main/install.md.

Domain skills are off by default. Set `BH_DOMAIN_SKILLS=1` to enable; see bottom section.

**If `BH_DOMAIN_SKILLS=1` and the task is site-specific, read every file in the matching `$BH_AGENT_WORKSPACE/domain-skills/<site>/` directory before inventing an approach.**

## Usage

**单行脚本（所有平台）：** `echo "print(page_info())" | browser-harness`

**多行脚本（所有平台通用，推荐）：** 先写 `.py` 文件，再用 `cat` pipe：
```bash
# 1. 写脚本到文件（在 Claude 中用 Write 工具）
# 2. cat 管道执行
cat /path/to/script.py | browser-harness
```

> ⚠️ macOS 上 heredoc (`<<'PY'`) 不可靠，经常无声失败。多行脚本一律走**写文件 → cat pipe** 路线。

- Helpers are pre-imported. `new_tab(url)` 创建并切换；`goto_url(url)` 当前页导航。
- **首次执行超时 30~60 秒**（daemon auto-start + CDP 握手）。
- **任务完成后必须清理**：`browser-harness --reload`。
- **后台静默模式**：设 `BH_BACKGROUND=1`，浏览器不抢焦点、不切标签页。`new_tab()` 在后台创建标签页，所有操作（JS 执行、DOM 操作、点击输入、截图）在后台标签页中正常工作，CDP 协议天然支持。

## Local Chrome

```
请求 → fast path → 执行脚本（60s）→ --reload 清理
         │ 失败 → --doctor 诊断 → 引导开启 chrome://inspect/#remote-debugging
```

首次慢是正常的，直接跑正式脚本即可。预热可选，仅在 daemon 确认停止时有必要。

## Page Workflow

1. **Pre-flight**:
   - `list_tabs()` — **必须第一步执行，零例外。** 永远不要假设当前标签页就是目标页。`current_tab()` 返回的是 harness session 绑定页，**不是**浏览器前台标签页。
   - `ensure_real_tab()` 确保落在真实页面。注意它可能静默切换标签页。
2. **确认标签页**: `list_tabs()` → `switch_tab(target_id)` — **必须用内置 helper，不能手动 CDP**。`list_tabs()` 返回 `[{target_id, targetId, title, url}]`，用 `target_id` 做切换。
3. **导航**: `goto_url(url)` 或 `new_tab(url)` → `wait_for_load()`
4. **操作/提取**: 见下方策略
5. **清理**: `browser-harness --reload` — 任务完成的最后一个动作永远是清理 daemon

> ⚠️ `current_tab()` 返回的是 harness session 绑定页，**不是**浏览器前台标签页。每次脚本开始都应 `list_tabs()` 确认。

## 数据提取策略（按优先级）

**提取前必须先验证页面有内容**：`js("document.body.innerText.length")` 应 > 0。跳过验证直接取内容是最常见的浪费根源。

1. **`js()`** — DOM 提取、JS 变量、内存数据。始终优先。多语句用 IIFE：`js("(() => { ... })()")`
2. **`page_info()`** — `{url, title, w, h, sx, sy, pw, ph}`，了解页面尺寸
3. **`scroll()` / `cdp("Input.*")`** — CDP 原生滚动/点击，穿透 Canvas
4. **`cdp("Network.*")`** — 网络拦截，API 响应提取
5. **`capture_screenshot()`** — 最后手段，验证码/纯图片页面

**点击**: 优先 `click_at_xy(x, y)` — 穿透 iframe/shadow/Canvas。需要定位时才截图。

## 任务结束检查清单

- [ ] `browser-harness --reload` 停止 daemon
- [ ] 确认无残留进程：
  ```powershell
  tasklist | findstr /i "browser_harness.daemon" || echo "clean"
  # macOS/Linux: pgrep -f "browser_harness.daemon" || echo "clean"
  ```
- [ ] 若有残留：`taskkill /F /FI "CommandLine like '%browser_harness%daemon%'"`（macOS: `pkill -f "browser_harness.daemon"`）

## Gotchas

1. **macOS heredoc 不可靠** — `<<'PY'` 经常无声失败（无输出无报错），统一用 `echo` / `cat file | browser-harness`。
2. **`printf` 含 `\n` 可能丢失输出** — 用 `echo` 单行或 `cat file` pipe 替代。
3. **pipe 多行中的引号冲突** — 管道传递的多行脚本里，Python 字符串内的引号容易与 shell 转义冲突。解决：**写 `.py` 文件再 `cat | browser-harness`**，避免一切 shell 转义问题。
4. **`js()` 内嵌多行 JS 函数** — Python 字符串字面量里直接写多行 JS 会报 `SyntaxError: unterminated string literal`。用 Python 三引号 `'''...'''` 包裹 JS 代码，换行不再打断字符串。
5. **永远不要假设当前标签页就是目标页** — 即使用户说"看我打开的 X 页面"，也必须先 `list_tabs()`。`page_info()` 可能返回完全不同的页面。
6. **切换标签页必须用 `switch_tab()`** — 手动 `cdp("Target.activateTarget")` 不会更新 harness session 绑定，后续 `js()` 仍指向旧页。
7. **`js()` 多语句必须用 IIFE 并立即调用** — `js("() => { return x; }")` 返回 `{}`。正确：`js("(() => { return x; })()")`
8. **首次执行慢是正常的** — daemon + CDP 握手需 30~60s，超时设 60s。
9. **忘记清理 daemon** — 每次任务结束必须 `--reload`。
10. **后台静默模式不激活标签页** — 设 `BH_BACKGROUND=1` 后，`switch_tab()` 不会调用 `Target.activateTarget`，标签页状态仅通过 CDP session 绑定更新（无窗口焦点变化）。如需验证当前绑定，用 `current_tab()`。

> 遇到其他问题？详见 `guides/debugging.md`。

## 📖 按需加载指引

遇到以下场景时，**先读对应的 guide 文件再行动**：

| 场景 | 判断信号 | 读什么 |
|------|---------|--------|
| 页面内容滚动后不变 | `body.innerText` 滚动前后相同 | `guides/virtual-rendering.md` |
| 不知道往哪里滚动 | `scroll()` 无效，`scrollTop` 不变 | `guides/scroll-discovery.md` |
| 需要从 SPA 提取结构化数据 | 需要 PWA 缓存 / Redux store / React fiber | `guides/memory-extraction.md` |
| 需要 CDP 底层事件 | Canvas 点击、网络拦截、a11y 树 | `guides/cdp-reference.md` |
| js() 返回 {} 或其他异常 | 调试 JS 表达式、管道故障 | `guides/debugging.md` |

**虚拟渲染页面的标准流程**（飞书、Notion、Google Docs 等）：
1. 先读 `guides/virtual-rendering.md` 判断类型
2. 优先走 `guides/memory-extraction.md` 内存提取
3. 内存无数据 → `guides/scroll-discovery.md` 滚动提取

## Interaction Skills

If you get stuck on a browser mechanic, check https://github.com/browser-use/browser-harness/tree/main/interaction-skills.

connection / cookies / cross-origin-iframes / dialogs / downloads / drag-and-drop / dropdowns / iframes / network-requests / print-as-pdf / profile-sync / screenshots / scrolling / shadow-dom / tabs / uploads / viewport

## Design Constraints

- Coordinate clicks default. CDP mouse events pass through iframes/shadow/cross-origin at the compositor level.
- Core helpers stay short. Task-specific additions → `$BH_AGENT_WORKSPACE/agent_helpers.py`.

## Domain Skills

Only when `BH_DOMAIN_SKILLS=1`. Search `$BH_AGENT_WORKSPACE/domain-skills/<host>/` before inventing an approach. `goto_url(...)` returns up to 10 skill filenames for the navigated host.

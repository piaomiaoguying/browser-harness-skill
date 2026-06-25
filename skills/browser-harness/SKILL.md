---
name: browser-harness
description: "Always use browser-harness for any web interaction: automation, scraping, testing, or site/app work."
---

# browser-harness

Direct browser control via CDP. For task-specific edits, use `agent-workspace/agent_helpers.py`. For setup, install, or connection problems, read https://github.com/browser-use/browser-harness/blob/main/install.md.

Domain skills are off by default. Set `BH_DOMAIN_SKILLS=1` to enable them; see the bottom section.

**If `BH_DOMAIN_SKILLS=1` and the task is site-specific, read every file in the matching `$BH_AGENT_WORKSPACE/domain-skills/<site>/` directory before inventing an approach.**

## Usage

**Linux / macOS (heredoc):**
```bash
browser-harness <<'PY'
print(page_info())
PY
```

**Windows (PowerShell):**
```powershell
# 方式一：直接传字符串（仅适合单行脚本）
"print(page_info())" | browser-harness

# 方式二：从文件传（适合多行脚本，最可靠）
Get-Content script.py | browser-harness
```

- Invoke as `browser-harness`. Use heredocs for multi-line commands.
- **PowerShell 不支持 `<<'PY'` heredoc 语法**，必须用管道传字符串或文件。多行脚本优先用写文件 + `Get-Content` 方式，避免 shell 转义问题。
- Helpers are pre-imported. `run.py` calls `ensure_daemon()` before `exec`.
- `new_tab(url)` 创建新标签页并自动切换到它；`goto_url(url)` 在当前绑定标签页导航。首次打开页面用 `new_tab()`，在已有页跳转用 `goto_url()`。
- The normal local flow attaches to the running Chrome/Chromium CDP endpoint. No browser ids or local profile selection.
- **首次执行超时预期**：daemon auto-start + CDP 握手需 30~60 秒，调用方应设 60s 超时。
- **任务完成后必须清理 daemon**：每次脚本执行完毕后，调用 `browser-harness --reload` 停止 daemon 进程，避免进程残留。

## Local Chrome

```
用户请求 ──► fast path ──► 执行脚本（超时 60s）──► browser-harness --reload 清理 daemon
                 │
           失败时 ──► --doctor 诊断：
                        ├─ Chrome 未运行 → 引导用户打开 Chrome
                        ├─ daemon 未起   → 自动拉起（首次慢，说明预期）
                        └─ CDP 不通     → 见下方指引
```

**fast path（默认）**：直接执行脚本，给足 60s 超时，执行完后调用 `browser-harness --reload` 停止 daemon。

**slow path（仅失败时）**：

```bash
browser-harness --doctor
```

If Chrome remote debugging is not enabled, the harness opens:

```text
chrome://inspect/#remote-debugging
```

Ask the user to tick "Allow remote debugging for this browser instance" and click Allow if Chrome shows a permission popup. Then retry the same `browser-harness` command.

**预拉起 daemon（可选）**：如果确定 daemon 尚未运行（如刚重启机器），可以先执行一次轻量调用来启动 daemon，后续调用不再有等待时间：

```bash
browser-harness <<'PY'
print('warmup')
PY
```

Windows 下改用管道传参。

**如果无法确定 daemon 是否存活**，直接跑正式脚本即可——首次调用会自动拉起 daemon，预热不是必须的。多余预热反而浪费一次调用。

## Page Workflow

- **[最高频] 每次脚本执行完毕后必须立即调用 `browser-harness --reload` 停止 daemon。** 不要等用户提醒——任务完成的最后一个动作永远是清理 daemon。
- **Pre-flight**: first call `ensure_real_tab()` to make sure we're on a real web page (not `chrome://` internal page, new tab page, or omnibox). If no real tab exists, it creates a blank one; if that fails, ask the user to open a web page manually. 注意：`ensure_real_tab()` 可能静默切换到另一个已有标签页——如果你需要保留当前标签页上下文，先调用 `list_tabs()` 确认位置。
- **Warm-up**：仅当明确知道 daemon 已停止（如刚执行过 `--reload`）时才有必要预热。连续多轮脚本执行时，第一轮启动 daemon 后后续无需预热。
- After navigation, call `wait_for_load()`.
- Login walls: stop and ask. Exception: use available SSO automatically when Chrome is already signed in; still stop for passwords, MFA, consent, or ambiguous account choice.
- **执行完毕必须清理 daemon**：见下方「任务结束检查清单」。

### 标签页管理（Tab 切换陷阱与最佳实践）

**核心原则：永远使用内置 helper，不要手动调用 CDP 底层 API 切换标签页。**

> **⚠️ 重要：`current_tab()` / harness 的"当前标签页"≠ 浏览器窗口前台标签页。** `current_tab()` 返回的是 harness 内部 CDP session 绑定的标签页，而浏览器前台标签页取决于你肉眼在 Chrome 窗口里看到的。当你在两次脚本执行之间手动切换浏览器标签页时，harness 的 session 绑定不会自动跟随——它仍然指向上一次 `switch_tab()` 设置的标签页。**每次脚本执行开始时，都应该主动调用 `list_tabs()` 确认当前绑定的是哪个页，必要时用 `switch_tab()` 纠正。**

```python
# ✅ 正确：使用内置 helper
tabs = list_tabs()                    # 列出所有 page 类型标签页
target = [t for t in tabs if "keyword" in t["url"]][0]
switch_tab(target)                    # 自动处理 activateTarget + attach + session 绑定
print(page_info())                    # ✅ 正确指向目标页
js("document.title")                  # ✅ 正确指向目标页

# ❌ 错误：手动 CDP 调用
cdp("Target.activateTarget", targetId="xxx")   # 只激活了 Chrome 层面
# page_info(), js() 仍然指向旧页，因为 harness 内部 session 未更新

# ✅ 其他标签管理 helper
new_tab("https://example.com")        # 新建标签页并自动切换到它
close_tab(target)                     # 关闭标签页
current_tab()                         # 获取当前绑定标签页信息
```

**原理**：`switch_tab()` 内部执行了三步操作：
1. `cdp("Target.activateTarget", ...)` — 激活 Chrome 层面的标签页
2. `cdp("Target.attachToTarget", ...)` — 获取新标签页的 CDP session
3. IPC `set_session` — 更新 harness 内部上下文绑定

缺少第 3 步，`page_info()`、`js()` 等所有后续调用都不会指向正确标签页。

> 同理，`new_tab()` / `goto_url()` 内部也调用了 `switch_tab()`，所以新建页面后无需额外操作即可直接使用。

## 脚本技巧与调试方法论

### 渐进式内容提取

不要一次性写复杂的长串选择器链。采用**先粗后精**的策略：

```python
# Step 1: 确认页面有内容
print(js("document.body.innerText.length"))       # 应 > 0

# Step 2: 确认目标选择器存在
print(js("document.querySelector('.target-class') !== null"))  # True/False

# Step 3: 确认表达式语法正确（排除管道转义问题）
print(js("'hello'"))                              # 应输出 hello，不是 {}

# Step 4: 提取精确内容
print(js("document.querySelector('.target-class')?.innerText || ''"))
```

每步确认结果合理再进入下一步。如果某步返回异常值，立刻定位问题类型（DOM 结构不对 / 语法不对 / 管道损坏），而不是继续调优选择器。

### `js()` 返回值异常调试三板斧

`js()` 将 JS 表达式的执行结果序列化为 Python 值返回。当返回值异常时，按以下顺序排查：

| 问题 | 嫌疑 | 验证方法 |
|------|------|----------|
| 返回 `{}` | JS 函数定义未执行（漏了 `()`） | 检查是否写成 `js("() => {...}")`，应为 `js("(() => {...})()")` |
| 返回 `None`/`null` | 选择器未匹配到元素 | `js("document.querySelector('...') !== null")` |
| 返回 `0` 或空字符串 | 页面无内容，或选择器匹配到空元素 | `js("document.body.innerText.length")` |

**关于 `js()` 的行为要点：**
- 单条表达式直接写：`js("document.title")`
- 多条语句必须用 **IIFE（立即调用函数表达式）** 包住并执行：`js("(() => { const x = 1; return x; })()")`
- 漏写最后的 `()` 时，`js()` 返回 `{}`（函数对象被序列化为空字典），**这不是页面问题，是语法错误**
- `js()` 自动处理 `awaitPromise=True`，所以 async IIFE 可以直接写：`js("(async () => { return await fetch('/api'); })()")`

### Shell 管道故障诊断与降级

PowerShell 的 here-string 和多行管道容易无声失败。诊断与降级流程：

```
多行脚本管道无声/报错
    │
    ├─ 立即用单行脚本测试链路是否畅通
    │   "print('ok')" | browser-harness
    │   │
    │   ├─ 无输出 → daemon/Chrome 问题，用 --doctor
    │   └─ 输出 ok → shell 转义问题，走降级
    │
    └─ 降级方案：写文件再 pipe
        Set-Content script.py -Value "..."
        Get-Content script.py | browser-harness
```

> **通用原则**：管道/heredoc 出问题后，不要原样重试。先诊断链路，再换更可靠的传参方式。

## 数据提取策略（按优先级从高到低）

**原则：优先用代码提取数据，截图+视觉分析作为最后手段。**

1. **`js()` / `cdp("Runtime.evaluate", ...)`** — DOM 提取、JS 变量读取、React fiber 遍历。这是最精确、最快的方法，应始终优先尝试。注意使用 IIFE 包裹多语句逻辑。
2. **`page_info()`** — 获取 `{url, title, w, h, sx, sy, pw, ph}`，了解页面尺寸和滚动位置，判断是否需要滚动。
3. **`cdp("Input.dispatchMouseEvent", ...)` + `scroll()`** — 当 JS 级 `WheelEvent` 无法驱动 Canvas/虚拟列表时，用 CDP 层原生事件触发真实滚动。
4. **`cdp("Network.xxx", ...)`** — 网络拦截，适合 API 响应数据提取（注意 CSRF/CORS 限制）。
5. **`capture_screenshot()`** — 仅在前 4 种方法都无法获取数据时使用。例如：验证码识别、纯图片/Canvas 渲染且无 a11y 覆盖层的页面。

### 点击/交互策略

- 优先 `click_at_xy(x, y)` — CDP 层坐标点击，穿透 iframe/shadow DOM，兼容 Canvas。
- 需要元素级交互时用 `fill_input()`、`press_key()`、`dispatch_key()`。
- 截图辅助点击定位：只有需要确定点击坐标时才截图 → 读取像素 → `click_at_xy`。

## CDP 底层能力参考

browser-harness 内置的 CDP 原生能力，处理复杂网页（Canvas 渲染、虚拟列表、WAF 保护）时尤其重要：

### CDP Input — 原生输入事件（穿透 Canvas/虚拟渲染）

```python
# CDP 原生鼠标滚轮 — 可驱动 react-virtualized、ag-grid 等虚拟列表
# 注意：飞书 RDK Canvas 可能连 CDP 原生滚动也不响应
scroll(x, y, dy=-300)                                        # 向下滚动 300px
scroll(x, y, dy=300)                                         # 向上滚动 300px
scroll(x, y, dy=-300, dx=0)                                  # 完整参数形式

# 完整 CDP 鼠标事件
cdp("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=-400)
cdp("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
cdp("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)

# 完整 CDP 键盘事件
cdp("Input.dispatchKeyEvent", type="keyDown", key="a", code="KeyA", ...)
cdp("Input.dispatchKeyEvent", type="char", text="a")
cdp("Input.dispatchKeyEvent", type="keyUp", key="a", code="KeyA", ...)

# 快捷封装
press_key("Enter")                                           # 支持 Enter/Tab/Escape/Arrow* 等
press_key("a")                                               # 单字符
```

### CDP Runtime — JS 执行

```python
# 返回 Python 值（通过 returnByValue）
cdp("Runtime.evaluate", expression="document.title")
cdp("Runtime.evaluate", expression="...", awaitPromise=True)

# 单条表达式——直接写
js("document.title")
js("document.querySelector('.class')?.innerText || ''")

# 多条语句——必须用 IIFE 包住并立即执行
js("(() => { const x = 1; return x; })()")

# 异步 IIFE
js("(async () => { const r = await fetch('/api/data'); return r.json(); })()")

# ⚠️ 常见错误：漏了最后的 () → 返回 {}（函数对象被序列化为空字典）
# 错误: js("() => { return 42; }")
# 正确: js("(() => { return 42; })()")
```

### CDP Network — 网络拦截

```python
cdp("Network.enable")
# 后续所有请求会出现在 drain_events() 中
events = drain_events()
```

### CDP DOM — 无障碍树/可访问性

```python
# 获取完整无障碍树（适用于 Canvas + a11y 覆盖层的页面）
cdp("Accessibility.getFullAXTree", depth=-1)

# DOM 查询
doc = cdp("DOM.getDocument", depth=-1)
node_id = cdp("DOM.querySelector", nodeId=root_id, selector=".my-class")["nodeId"]
```

## 复杂页面场景应对指南

### Canvas/WebGL 虚拟渲染（如飞书 RDK、Figma、Google Sheets）

**特征**：DOM 几乎是空的，主要内容在 Canvas 上渲染。

**首选：内存数据提取（避免与 Canvas 较劲）**

1. **PWA 缓存**：`js()` 读取 `window.__PWA_CACHE_PREFETCH`，飞书等 PWA 应用常将完整 API 响应缓存于此，数据结构化且完整
2. **全局 Store**：`js()` 搜索 `window` 下名称含 `store`/`state`/`redux`/`cache` 的对象
3. **React fiber**：从 `#root` 的 `__reactContainer$...` / `__reactFiber$...` 遍历 `memoizedState` 查找列表数据
4. **`window` 遍历**：`Object.keys(window)` 搜索名称含 story/project/data 的全局变量

**备选：Canvas 交互提取（当内存数据不可用时）**

1. 先用 `js()` 查找 `.rdk-a11y-element` 或类似的可访问性覆盖层元素
2. 用 `cdp("Accessibility.getFullAXTree")` 获取无障碍树
3. 尝试 `scroll(x, y, dy=-300)` 驱动 CDP 原生滚动（部分 Canvas 引擎响应，但飞书 RDK 已知不响应）
4. 如果 `page_info()` 中 `sy` 不变，说明滚动无效→回到内存提取路线
5. 每轮滚动后立即提取 a11y 数据（它们是瞬态的），按坐标去重合并

### 滚动动态加载列表

1. 先 `page_info()` 获取 `{pw, ph}` 了解页面总高度
2. 先尝试 `js("window.__PWA_CACHE_PREFETCH")` 或全局 store 直接批量获取全量数据
3. 内存数据不可用时，用 `scroll(x, y, dy=-300)` 逐步滚动
4. 每轮用 `js()` 提取当前视口数据，去重
5. 连续多轮无新数据且 `sy` 不变→滚动无效，放弃滚动路径

## 任务结束检查清单

每次 browser-harness 任务完成后**必须**逐项确认：

- [ ] 已调用 `browser-harness --reload` 停止 daemon
- [ ] 已确认无残留进程：
  ```bash
  # macOS / Linux
  pgrep -f "browser_harness.daemon" || echo "clean"
  ```
  ```powershell
  # Windows
  tasklist | findstr /i "browser_harness.daemon" || echo "clean"
  ```
- [ ] 若有残留，强制清理：
  ```bash
  # macOS / Linux
  pkill -f "browser_harness.daemon"
  ```
  ```powershell
  Windows
  taskkill /F /FI "CommandLine like '%browser_harness%daemon%'"
  ```

## Interaction Skills

If you get stuck on a browser mechanic, check https://github.com/browser-use/browser-harness/tree/main/interaction-skills.

- connection.md
- cookies.md
- cross-origin-iframes.md
- dialogs.md
- downloads.md
- drag-and-drop.md
- dropdowns.md
- iframes.md
- network-requests.md
- print-as-pdf.md
- profile-sync.md
- screenshots.md
- scrolling.md
- shadow-dom.md
- tabs.md
- uploads.md
- viewport.md

## Design Constraints

- Coordinate clicks default. CDP mouse events pass through iframes/shadow/cross-origin at the compositor level.
- Keep the connection model simple: local Chrome CDP endpoint via the default daemon.
- Core helpers stay short. Put task-specific helper additions in `$BH_AGENT_WORKSPACE/agent_helpers.py`.

## Gotchas（按影响排序）

1. **[高频] PowerShell 不支持 heredoc 语法**。Windows 下多行脚本必须写文件再用 `Get-Content` pipe，不能用 `<<'PY'`。如果管道无声失败，先用单行脚本诊断链路，再降级到文件管道。
2. **[高频] 首次执行慢**。daemon auto-start + CDP 握手需 30~60 秒。脚本超时应设为 60s。预热仅在第一轮或 daemon 已停止时有必要；连续多轮脚本无需重复预热。
3. **[高频] `chrome://inspect/#remote-debugging` 必须启用** 才能控制本地 Chrome。
4. **[高频] 切换标签页必须用 `switch_tab()`，不能直接调 CDP**。手动 `cdp("Target.activateTarget", ...)` 只会激活 Chrome 层面的标签页，不会更新 harness 内部的 session 绑定。此后 `page_info()`、`js()` 所有调用仍指向旧页。必须使用 `switch_tab(target)`，它内部完成了 activateTarget + attachToTarget + session 绑定三步。同理，新建标签页要用 `new_tab()` 而非 `cdp("Target.createTarget")`。
5. **[高频] `js()` 的多语句写法必须用 IIFE 并立即调用**。写成 `js("() => { return x; }")` 会返回 `{}`。正确写法是 `js("(() => { return x; })()")`。如果 `js()` 返回 `{}`，先检查是否漏了 `()`。
6. **[高频] Canvas/WebGL 虚拟渲染页面不响应 `js()` 派发的 `WheelEvent`**。飞书 RDK、Figma、Google Sheets 等将内容渲染到 Canvas 上，JS 合成的 `WheelEvent` 对它们的滚动机制无效。**优先尝试 CDP 原生 `scroll(x, y, dy=-300)`，但飞书 RDK 等特别顽固的引擎可能连 CDP 滚动也不响应**——此时应走内存数据提取路线（PWA 缓存、全局 store、React fiber）。
7. **[高频] PWA 应用的内存缓存是数据金矿**。飞书等 PWA 应用会将完整 API 响应缓存在 `window.__PWA_CACHE_PREFETCH` 中，数据是结构化 JSON，比 Canvas/a11y/DOM 提取都可靠。**在尝试 DOM/Canvas 交互之前，先用 `js()` 探一下 `window.__PWA_CACHE_PREFETCH` 和全局 store 对象。**
8. **[中频] Chrome 远程调试权限弹窗** — 等待用户点击 Allow。
9. **[中频] `current_tab()` 返回的是 harness session 绑定页，不是浏览器前台标签页**。你在两次脚本执行之间手动切换浏览器标签页后，harness 的 session 绑定不会自动跟随——它仍然指向上一次 `switch_tab()` 设置的那个页面。**每次脚本开始时应当用 `list_tabs()` 确认当前绑定，必要时重新 `switch_tab()`。**
10. **[中频] CDP target 顺序 ≠ Chrome 标签页栏顺序**。不要依赖 target 列表顺序来判断当前页。
11. **[中频] Omnibox 弹出层、`chrome://` 内部页、新标签页** 都不是真实工作标签页。用 `ensure_real_tab()` 确保落在真实页面上，但注意它可能静默切换到其他已有标签页。
12. **[中频] 虚拟列表的 a11y 覆盖层是瞬态的**。`.rdk-a11y-element` 等元素只在当前视口内存在，滚动后旧元素消失，新元素出现。必须每轮滚动后立即提取数据，不能等所有滚动完成后再收集。
13. **[中频] `scrollTop` 赋值对 Canvas 虚拟列表无效**。Canvas 引擎不通过 DOM scrollTop 管理滚动位置，通过 `js("element.scrollTop = N")` 设置滚动位置无效果。
14. **[中频] 忘记清理 daemon** — 见「任务结束检查清单」。
15. **[低频] `BU_CDP_URL` 是 HTTP DevTools 端点**，daemon 会自动转成 WebSocket。

## Domain Skills

Only applies when `BH_DOMAIN_SKILLS=1`. Otherwise ignore domain skills.

When enabled, search `$BH_AGENT_WORKSPACE/domain-skills/<host>/` before inventing an approach. `goto_url(...)` returns up to 10 skill filenames for the navigated host.

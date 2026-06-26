# 调试指南

`js()` 返回值异常、Shell 管道故障、`list_tabs()` 字段不匹配的诊断方法。

## `list_tabs()` 返回结构

每个元素是一个 dict：`{target_id, targetId, title, url}`。用 `target_id` 做 `switch_tab()`，**不要猜字段名**——不确定时先 `print(t)` 看完全部键名，一轮确认比猜错重试快。

```python
tabs = list_tabs()
for t in tabs:
    print(t)           # 先看有哪些字段
# 然后用 t['target_id'] 切换
```

## js() 返回值异常

### 三板斧排查

| 问题 | 嫌疑 | 验证方法 |
|------|------|----------|
| 返回 `{}` | JS 函数定义未执行（漏了 `()`） | 检查是否写成 `js("() => {...}")`，应为 `js("(() => {...})()")` |
| 返回 `None`/`null` | 选择器未匹配到元素 | `js("document.querySelector('...') !== null")` |
| 返回 `0` 或空字符串 | 页面无内容，或选择器匹配到空元素 | `js("document.body.innerText.length")` |

### js() 行为要点

- **单条表达式**直接写：`js("document.title")`
- **多条语句**必须用 IIFE 包住并执行：`js("(() => { const x = 1; return x; })()")`
- 漏写最后的 `()` → 返回 `{}`（函数对象被序列化为空字典），**这不是页面问题，是语法错误**
- async IIFE 可以直接写：`js("(async () => { return await fetch('/api'); })()")`

### Object reference chain is too long

CDP 序列化深层嵌套对象时会报此错。

```python
# ❌ 错误：序列化整个 fiber/store
js('document.getElementById("root").__reactFiber$xxx')

# ✅ 正确：只提取需要的字段
js('''() => {
  const fiber = document.getElementById("root").__reactFiber$xxx;
  return { tag: fiber?.tag, type: fiber?.type?.name };
}()''')
```

### IIFE 模板速查

```python
# 只读一条
js("document.querySelector('.cls')?.innerText || ''")

# 多语句
js("(() => { const a = 1; const b = 2; return a + b; })()")

# 异步
js("(async () => { const r = await fetch('/api'); return r.json(); })()")

# 返回数组/对象（多行用三引号）
js('''(() => {
  const items = document.querySelectorAll(".item");
  return Array.from(items).map(el => el.innerText);
})()''')
```

## Shell 管道故障

### macOS heredoc 不可靠

macOS 上 `browser-harness <<'PY' ... PY` 经常**无声失败**——没有任何输出也没有报错，直接返回。原因疑似 shell 与 daemon stdin 交互问题。

```bash
# ❌ 不可靠，经常无声失败
browser-harness <<'PY'
print(list_tabs())
PY

# ✅ 单行：echo pipe
echo "print(list_tabs())" | browser-harness

# ✅ 多行：写文件 + cat pipe（所有平台通用，最可靠）
cat script.py | browser-harness
```

### `printf` 含 `\n` 丢失输出

`printf` 中的 `\n` 可能被 shell 解释后打断管道，导致无输出：

```bash
# ❌ 可能无输出
printf 'print(list_tabs())\nprint(page_info())\n' | browser-harness

# ✅ 用 echo 单行，或多行写文件 + cat
echo 'print(list_tabs())' | browser-harness
```

### 管道多行脚本中的引号冲突

Shell 管道传递多行脚本时，Python 字符串内的引号容易与 shell 转义规则冲突：

```bash
# ❌ f-string 中 info["url"] 的双引号被子 shell 解释
printf 'info = page_info(); print(f"URL: {info[\"url\"]}")' | browser-harness
# → SyntaxError: unexpected character after line continuation character
```

**根本解法：涉及任何复杂脚本，一律写 `.py` 文件再 cat pipe。**

### Python 三引号包裹多行 JS

`js()` 的参数是一个 JS 字符串。管道模式下 Python 字符串字面量里的换行会打断语法：

```python
# ❌ SyntaxError: unterminated string literal
text = js("(() => {
  const el = document.querySelector('.cls');
  return el?.innerText || '';
})()")

# ✅ 用 Python 三引号包裹多行 JS
text = js("""(() => {
  const el = document.querySelector('.cls');
  return el?.innerText || '';
})()""")

# ✅ 也可以单引号三引号（避免与 JS 内的双引号冲突）
text = js('''(() => {
  const el = document.querySelector('.cls');
  return el?.innerText || '';
})()''')
```

### 管道无声失败诊断

```
多行脚本管道无声/报错
    │
    ├─ 用单行脚本测试链路
    │   "print('ok')" | browser-harness
    │   │
    │   ├─ 无输出 → daemon/Chrome 问题，用 --doctor
    │   └─ 输出 ok → shell 转义问题，走降级
    │
    └─ 降级方案：写文件再 pipe
        Set-Content script.py -Value "..."
        Get-Content script.py | browser-harness
```

**通用原则**：管道/heredoc 出问题后，不要原样重试。先诊断链路，再换更可靠的传参方式。

### 渐进式提取（避免一次性写复杂脚本）

```python
# Step 1: 确认页面有内容
print(js("document.body.innerText.length"))       # 应 > 0

# Step 2: 确认目标选择器存在
print(js("document.querySelector('.target-class') !== null"))  # True/False

# Step 3: 确认表达式语法正确
print(js("'hello'"))                              # 应输出 hello，不是 {}

# Step 4: 提取精确内容
print(js("document.querySelector('.target-class')?.innerText || ''"))
```

### SVG 元素的 `className` 陷阱

`querySelectorAll` 可能匹配到 SVG 元素（如搜索图标），此时 `e.className` 返回的是 `SVGAnimatedString` 对象，不是普通字符串。直接调用 `.slice()`、`.includes()` 等字符串方法会抛 `TypeError: ... is not a function`。

```python
# ❌ 报错 — 匹配到的 SVG 元素 className 不是字符串
js("""(() => {
  const els = document.querySelectorAll('[class*="foo"]');
  return Array.from(els).map(e => ({ class: e.className.slice(0, 50) }));
})()""")

# ✅ 用 String() 强制转换，对所有元素类型都安全
js("""(() => {
  const els = document.querySelectorAll('[class*="foo"]');
  return Array.from(els).map(e => ({ class: String(e.className || '').slice(0, 50) }));
})()""")
```

**何时会触发：** 任何带 SVG 图标的页面（搜索按钮、社交媒体图标、装饰图形等），只要选择器同时命中 HTML 和 SVG 元素就可能出现。`className` 是最高频受害者，其他属性如 `.class`、`.style` 对 SVG 行为也不同。

**排查方法：** 看到 `TypeError: ... is not a function` 且表达式用到了 `.className`，检查 `querySelectorAll` 的范围是否可能包含 `<svg>` — 打印 `e.tagName` 即可确认。

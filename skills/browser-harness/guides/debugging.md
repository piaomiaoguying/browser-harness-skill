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
js('(() => { \
  const fiber = document.getElementById("root").__reactFiber$xxx; \
  return { tag: fiber?.tag, type: fiber?.type?.name }; \
})()')
```

### IIFE 模板速查

```python
# 只读一条
js("document.querySelector('.cls')?.innerText || ''")

# 多语句
js("(() => { const a = 1; const b = 2; return a + b; })()")

# 异步
js("(async () => { const r = await fetch('/api'); return r.json(); })()")

# 返回数组/对象
js('(() => { \
  const items = document.querySelectorAll(".item"); \
  return Array.from(items).map(el => el.innerText); \
})()')
```

## Shell 管道故障

### PowerShell heredoc 不可用

PowerShell 不支持 `<<'PY'` 语法。必须用管道或文件：

```powershell
# 单行脚本
"print(page_info())" | browser-harness

# 多行脚本（推荐）
Set-Content script.py -Value @"
print(page_info())
print(list_tabs())
"@
Get-Content script.py | browser-harness
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

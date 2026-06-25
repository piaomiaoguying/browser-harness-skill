# 滚动容器发现与内容提取 Pipeline

适用场景：`scroll()` 或 `window.scrollTo()` 无效，需要找到真正的滚动容器并提取完整内容。

## Step 1：发现滚动容器

SPA 页面几乎从不把内容滚动挂在 `window` 上。必须先找到正确的容器。

```python
# 暴力扫描：找所有 scrollHeight > clientHeight 的元素
js('(() => { \
  const all = document.querySelectorAll("*"); \
  const result = []; \
  for (const el of all) { \
    if (el.scrollHeight > el.clientHeight + 50 && el.clientHeight > 100) { \
      result.push({ \
        tag: el.tagName, \
        cls: (el.className || "").toString().substring(0, 80), \
        sh: el.scrollHeight, \
        ch: el.clientHeight, \
        st: el.scrollTop, \
        overflow: getComputedStyle(el).overflow \
      }); \
    } \
  } \
  return result; \
})()')
```

**筛选规则**：
- 排除：className 含 `sidebar` / `modal` / `drawer` / `dropdown` / `tooltip` / `popup`
- 优先：面积最大（scrollHeight × clientHeight）、`overflow: auto/scroll`
- 验证：修改 `scrollTop` 后检查 `innerText` 是否变化

```python
# 验证候选容器是否是目标
js('(() => { \
  const el = document.querySelector(".candidate-class"); \
  el.scrollTop = 500; \
  return { scrollTop: el.scrollTop, changed: el.scrollTop === 500 }; \
})()')
```

## Step 2：计算滚动参数

```python
info = js('(() => { \
  const el = document.querySelector(".scroll-container"); \
  return { \
    scrollHeight: el.scrollHeight, \
    clientHeight: el.clientHeight, \
    maxScroll: el.scrollHeight - el.clientHeight, \
    currentScroll: el.scrollTop \
  }; \
})()')
# scrollHeight: 总高度, clientHeight: 视口高度, maxScroll: 最大滚动距离
```

## Step 3：逐步滚动 + 提取

```python
import time

container = ".scroll-container"  # 由 Step 1 确定
step = 400                       # 步长，视内容密度调整（200~600）
scrollHeight = int(js(f'document.querySelector("{container}").scrollHeight'))

all_content = []
seen = set()
pos = 0

while pos <= scrollHeight + step:
    # 滚动
    js(f'(() => {{ document.querySelector("{container}").scrollTop = {pos}; }})()')
    time.sleep(0.6)  # 等待渲染，虚拟列表需要 0.3~1s

    # 提取当前视口内容
    text = js('document.body.innerText')
    if text not in seen:
        seen.add(text)
        all_content.append(text)

    # 检查 scrollHeight 是否增长（动态加载内容）
    newH = int(js(f'document.querySelector("{container}").scrollHeight'))
    if newH > scrollHeight:
        scrollHeight = newH  # 更新上限

    pos += step
```

## Step 4：去重合并

虚拟渲染的相邻帧有大量重叠内容。合并策略：

```python
# 方法 A：基于文本行去重（适合长文档）
all_lines = set()
for snapshot in all_content:
    for line in snapshot.split('\n'):
        if line.strip() and len(line.strip()) > 2:
            all_lines.add(line.strip())

# 方法 B：基于 block ID 去重（如果 DOM 有 data-block-id）
seen_ids = set()
for i in range(block_count):
    block_id = js(f'document.querySelectorAll("[data-block-id]")[{i}].getAttribute("data-block-id")')
    if block_id not in seen_ids:
        seen_ids.add(block_id)
        text = js(f'document.querySelectorAll("[data-block-id]")[{i}].innerText')
        # 收集 text
```

## 处理非线性跳跃

虚拟渲染引擎可能在某些位置跳过内容（如从 2.3 直接跳到 3.1）。

**检测方法**：检查合并结果中是否包含预期的结构标记（章节标题、编号等）。

**应对**：在缺失区间缩小步长重试：

```python
# 如果检测到从 "2.3" 跳到 "3.1"，在该区间用更小步长重试
for pos in range(3000, 5500, 150):  # step 从 400 缩小到 150
    js(f'(() => {{ document.querySelector("{container}").scrollTop = {pos}; }})()')
    time.sleep(0.5)
    # 提取并检查是否包含缺失内容
```

## 完整模板

```python
import time

def extract_virtual_content(container_selector, step=400, wait=0.6):
    """从虚拟渲染容器中提取完整文本内容"""
    js(f'(() => {{ document.querySelector("{container_selector}").scrollTop = 0; }})()')
    time.sleep(1)

    scrollHeight = int(js(f'document.querySelector("{container_selector}").scrollHeight'))
    all_texts = []
    seen = set()
    pos = 0

    while pos <= scrollHeight + step:
        js(f'(() => {{ document.querySelector("{container_selector}").scrollTop = {pos}; }})()')
        time.sleep(wait)

        text = js('document.body.innerText')
        if text not in seen:
            seen.add(text)
            all_texts.append(text)

        newH = int(js(f'document.querySelector("{container_selector}").scrollHeight'))
        if newH > scrollHeight:
            scrollHeight = newH
        pos += step

    return "\n\n".join(all_texts)
```

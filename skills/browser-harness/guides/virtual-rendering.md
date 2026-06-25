# 虚拟渲染检测与应对策略

适用场景：页面使用 Canvas/WebGL/虚拟列表渲染，DOM 中几乎无内容，滚动后 `innerText` 不变。

## 检测方法

```python
# Step 1: 检查页面文本量
js("document.body.innerText.length")  # < 500 字符 → 可疑

# Step 2: 滚动后对比
before = js("document.body.innerText.length")
# ... 执行滚动 ...
after = js("document.body.innerText.length")
# before == after → 高度疑似虚拟渲染

# Step 3: 检查虚拟渲染特征
js('(() => { \
  const cls = document.body.innerHTML; \
  return cls.includes("virtual") || cls.includes("canvas") || \
         cls.includes("rdk-a11y") || cls.includes("bear-virtual") || \
         cls.includes("placeholder"); \
})()')
```

## 常见虚拟渲染技术

| 网站/框架 | 技术 | 滚动响应 |
|-----------|------|---------|
| 飞书文档 | bear-virtual (Canvas+DOM) | 不响应任何滚动 |
| Google Sheets/Docs | Canvas | 不响应 JS 滚动 |
| Figma | Canvas/WebGL | 不响应 |
| ag-grid / AntD Table | react-virtualized / rc-virtual-list | 响应 CDP scroll |
| Notion | 自研虚拟列表 | 响应 CDP scroll |
| Twitter/X 信息流 | 虚拟列表 | 响应 CDP scroll |

## 应对策略（按优先级）

### 策略 1：内存数据提取（首选）

详见 `memory-extraction.md`。

### 策略 2：程序化滚动 + 逐帧提取

详见 `scroll-discovery.md`。

适用于 DOM 中有文本内容但被虚拟化的列表（ag-grid、AntD Table、Notion 数据库等）。

### 策略 3：无障碍树（a11y）

```python
# 获取完整无障碍树
cdp("Accessibility.getFullAXTree", depth=-1)

# 或先查找 a11y 覆盖层元素
js('document.querySelectorAll(".rdk-a11y-element").length')
```

> ⚠️ a11y 覆盖层是**瞬态的**——只在当前视口存在，滚动后旧元素消失。必须每轮滚动后**立即**提取。

### 策略 4：截图 + OCR（最后手段）

仅当以上策略全部失败时使用。适合验证码、纯图片渲染且无 a11y 覆盖的页面。

## 关键陷阱

1. **`scrollTop` 赋值对 Canvas 无效** — Canvas 引擎不通过 DOM scrollTop 管理滚动
2. **JS 合成的 `WheelEvent` 对 Canvas 无效** — 必须用 CDP 原生 `scroll()`
3. **飞书 RDK 连 CDP `scroll()` 也不响应** — 只能走内存提取路线
4. **虚拟渲染的块回收有延迟** — 某些滚动位置可能重复渲染同一批块，另一些位置可能跳过内容
5. **不要假设滚动是线性的** — 合并策略应基于内容特征（章节标题、block ID），而非滚动位置

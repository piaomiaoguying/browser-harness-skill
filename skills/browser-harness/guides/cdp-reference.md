# CDP 底层能力参考

browser-harness 内置的 CDP 原生能力，处理复杂网页（Canvas 渲染、虚拟列表、WAF 保护）时尤其重要。

## CDP Input — 原生输入事件

穿透 iframe/shadow DOM/Canvas，直接在合成器层面派发。

```python
# 鼠标滚轮 — 可驱动 react-virtualized、ag-grid 等虚拟列表
scroll(x, y, dy=-300)                          # 向下滚动 300px
scroll(x, y, dy=300)                           # 向上滚动 300px
scroll(x, y, dy=-300, dx=0)                    # 完整参数形式

# 完整 CDP 鼠标事件
cdp("Input.dispatchMouseEvent", type="mouseWheel", x=x, y=y, deltaX=0, deltaY=-400)
cdp("Input.dispatchMouseEvent", type="mousePressed", x=x, y=y, button="left", clickCount=1)
cdp("Input.dispatchMouseEvent", type="mouseReleased", x=x, y=y, button="left", clickCount=1)

# 键盘事件
cdp("Input.dispatchKeyEvent", type="keyDown", key="a", code="KeyA")
cdp("Input.dispatchKeyEvent", type="char", text="a")
cdp("Input.dispatchKeyEvent", type="keyUp", key="a", code="KeyA")

# 快捷封装
press_key("Enter")                             # 支持 Enter/Tab/Escape/Arrow* 等
press_key("a")                                 # 单字符
```

## CDP Runtime — JS 执行

```python
# 返回 Python 值（通过 returnByValue）
cdp("Runtime.evaluate", expression="document.title")
cdp("Runtime.evaluate", expression="...", awaitPromise=True)

# 等价快捷方式
js("document.title")
js("(() => { const x = 1; return x; })()")      # IIFE
js("(async () => { return await fetch('/api'); })()")  # async IIFE
```

## CDP Network — 网络拦截

```python
cdp("Network.enable")
# 后续所有请求会出现在 drain_events() 中
events = drain_events()
```

## CDP DOM — 无障碍树/查询

```python
# 获取完整无障碍树（适用于 Canvas + a11y 覆盖层的页面）
cdp("Accessibility.getFullAXTree", depth=-1)

# DOM 查询
doc = cdp("DOM.getDocument", depth=-1)
node_id = cdp("DOM.querySelector", nodeId=root_id, selector=".my-class")["nodeId"]
```

# 内存数据提取

适用场景：需要从 SPA 应用的内存中直接提取结构化数据，绕过 DOM/Canvas 渲染。

**原则：内存数据比 DOM/Canvas 提取更可靠、更完整、更快。在尝试任何页面交互之前，先探测内存。**

## 探测流程（按优先级）

### Step 1：PWA / SSR 缓存

```python
# 飞书等 PWA 应用
js("window.__PWA_CACHE_PREFETCH")

# Next.js
js("window.__NEXT_DATA__")

# Nuxt.js
js("window.__NUXT__")

# 通用 SSR 初始状态
js("window.__APP_INITIAL_STATE__")
js("window.__INITIAL_STATE__")
```

### Step 2：状态管理 Store

```python
# Redux (飞书、React 应用常见)
js('(() => { \
  const s = window.__store__ || window.store; \
  if (!s || !s.getState) return null; \
  return Object.keys(s.getState()); \
})()')

# Pinia / Vuex (Vue 应用)
js('(() => { \
  const app = document.querySelector("#app")?.__vue_app__; \
  if (!app) return null; \
  return Object.keys(app.config.globalProperties); \
})()')

# 通用搜索
js('Object.keys(window).filter(k => \
  /store|state|redux|cache|pinia|vuex/i.test(k) \
).slice(0, 20)')
```

找到 store 后，按层级深入：

```python
# 列出 state 顶层 key
js('(() => { \
  const state = window.__store__.getState(); \
  return Object.keys(state); \
})()')

# 读取特定模块
js('window.__store__.getState().docx')

# 如果 state 太大，只看前 N 个 key
js('(() => { \
  const state = window.__store__.getState().targetModule; \
  return Object.keys(state).slice(0, 30); \
})()')
```

### Step 3：React Fiber 遍历

适合提取列表数据、API 响应缓存等组件内部状态。

```python
# 获取 fiber root
js('(() => { \
  const root = document.getElementById("root"); \
  const key = Object.keys(root).find(k => \
    k.startsWith("__reactContainer$") || k.startsWith("__reactFiber$") \
  ); \
  return key || null; \
})()')

# 遍历 memoizedState（链表结构，需要递归）
js('(() => { \
  const root = document.getElementById("root"); \
  const key = Object.keys(root).find(k => k.startsWith("__reactFiber$")); \
  if (!key) return null; \
  let fiber = root[key]; \
  const states = []; \
  let depth = 0; \
  while (fiber && depth < 20) { \
    if (fiber.memoizedState) { \
      states.push({ \
        tag: fiber.type?.name || fiber.type?.displayName || String(fiber.tag), \
        hasState: true \
      }); \
    } \
    fiber = fiber.child; \
    depth++; \
  } \
  return states; \
})()')
```

> ⚠️ React Fiber 遍历可能触发 "Object reference chain is too long" 错误。避免序列化整个 fiber 节点，只提取需要的字段。

### Step 4：全局变量扫描

```python
# 按关键词搜索
js('Object.keys(window).filter(k => \
  /doc|wiki|content|article|data|page|block|editor/i.test(k) && \
  typeof window[k] === "object" && window[k] !== null \
).slice(0, 20)')

# 检查特定命名空间（如飞书 docx）
js('window.docx ? Object.keys(window.docx).slice(0, 20) : null')
```

### Step 5：网络请求拦截

如果页面还在加载中，可以拦截 API 响应获取原始数据。

```python
cdp("Network.enable")
# 刷新页面或触发操作
# 然后读取事件
events = drain_events()
api_responses = [e for e in events if "api" in e.get("params", {}).get("request", {}).get("url", "")]
```

## 探测结果记录模板

每次探测后记录结果，帮助后续判断：

```
PWA 缓存: [有/无] __PWA_CACHE_PREFETCH → keys: [...]
Redux Store: [有/无] window.__store__ → state keys: [...]
目标数据位置: state.xxx.yyy
数据结构: { type: "array", length: N, sample: {...} }
```

## 常见错误

| 错误 | 原因 | 解决 |
|------|------|------|
| `Object reference chain is too long` | 序列化了过深的嵌套对象 | 只提取需要的字段，避免序列化整个 fiber/store |
| `getState is not a function` | 不是 Redux store | 尝试 Pinia/Vuex 或其他状态管理 |
| 返回 `null` 但页面有内容 | 数据在子组件 state 中 | 走 React Fiber 遍历 |

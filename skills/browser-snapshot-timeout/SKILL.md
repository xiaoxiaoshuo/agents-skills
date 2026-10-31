---
name: browser-snapshot-timeout
description: "DSH 浏览器工具在单页应用（SPA）上超时、卡住或返回「No visible changes」时的诊断与恢复流程。适用于 browser_snapshot / browser_get_text 返回 'tool call timed out after 90000ms'、点击后报无可见变化、或页面持续刷新（监控面板、实时图表、聊天界面）导致快照迟迟不稳定的场景。"
whenToUse: "当 browser_snapshot 或 browser_get_text 超时、页面读取卡住、或 SPA 页面点击后报 No visible changes 但实际状态已变时。"
---

# 浏览器工具超时与 SPA 取内容

## 一句话原则

**超时不等于浏览器挂了。** 先分辨「桥梁死」还是「单页读取卡住」，再按成本从低到高换手段。
连续重试同一个超时调用是最贵的做法——每次都烧满 90 秒上限。

## 症状对照表

| 症状 | 含义 |
|---|---|
| `browser_snapshot` 返回 `tool call timed out after 90000ms` | 页面 DOM 读取阻塞，多为 settle 等不到 |
| `browser_get_text` **同时**超时 | 不是序列化格式问题，是「取内容」这一步整体卡住 |
| `browser_list_tabs` 秒回 | **桥梁正常**，可排除插件/连接层故障 |
| `browser_click` 报 "No visible changes"，但 title/URL 已变 | 路由已切换，只是无障碍树没重算 |
| `snapshot delta=true` 报无变化 | 同上，delta 判定失效 |

## 恢复阶梯（严格按顺序，越往下越重）

### 1. 先探活，别猜

`browser_list_tabs` 只读 CDP 目标列表，**不碰 DOM，永远秒回**。

- 能返回 → 桥梁活着，问题在页面
- 也超时 → 才是真正的连接层故障

顺手从返回里读出当前 URL 和 title，**这本身就是有效信息源**。

### 2. 缩小取景范围

同一页面，全量快照可能几秒出，也可能卡死。按此优先级降级：

1. `browser_snapshot` + `region`（如 `main`）
2. `browser_snapshot` + `delta=true`
3. `browser_get_text`（纯文本，比无障碍树便宜一个量级）

### 3. 直接跳路由，别点导航

SPA 的 hash/history 路由可以直接 `browser_navigate` 到目标地址，
比「点导航链接 → 等渲染 → 再取快照」少一次交互、少一次超时风险。

### 4. reload + 显式等待（最可靠的一招）

```
browser_reload
→ browser_wait(1500~3000ms)
→ browser_snapshot
```

首次 hydration 阶段的竞态是超时主因之一。重载后页面已完整，再给固定等待，成功率最高。

### 5. 放弃 UI，改用非浏览器验证

如果上面都没拿到内容，**不要在浏览器里反复纠缠**。
后端状态几乎总能绕过 UI 直接验证：

```bash
curl -s http://127.0.0.1:PORT/api/endpoint | python3 -m json.tool
```

UI 只是同一份数据的一个视图。**能证明状态的是数据源，不是像素。**

## 根因（推断，未完全证实）

- SPA 带常驻 WebSocket 推送（流量曲线、连接数、实时延迟）时 DOM 永不稳定，
  snapshot 的 settle 判定可能一直等到 90s 上限
- 首次打开时 hydration 较重，存在竞态
- `list_tabs` 走轻路径不阻塞，与 DOM 读取不是同一条链路

如需证伪/证实，做对照实验：**静态 HTML 页 vs 持续动画面板**，
各执行「open → 立即 snapshot」，看是否只有后者必现超时。

## 反模式

- ❌ 超时后立刻重试同一个调用 —— 每次再烧 90 秒
- ❌ 因为 snapshot 超时就断定「浏览器坏了」—— 先 `list_tabs` 探活
- ❌ 看到 "No visible changes" 就以为操作失败 —— 先查 API / URL / title
- ❌ 只靠点 UI 验证后端逻辑 —— 优先直接打 API

## 实测案例（2026-10-31，mihomo 面板）

打开 `http://127.0.0.1:9090/ui/`（metacubexd，Nuxt SPA，概览页有常驻 WebSocket 图表）后：

1. `browser_snapshot` → 90000ms 超时
2. `browser_get_text` → 同样 90000ms 超时
3. `browser_list_tabs` → **秒回**，确认桥梁正常，并拿到 title「概览 - MetaCubeXD」
4. `browser_navigate` 到 `#/proxies` → `browser_get_text` 成功
5. `browser_click` 导航项 → "No visible changes"
6. `browser_reload` + `browser_wait(2500)` → 完整拿到代理页（8 个分组 + 2 个提供者）

**结论：第 3 步的 list_tabs 探活 + 第 6 步的 reload/wait，是这套故障的标准解法。**

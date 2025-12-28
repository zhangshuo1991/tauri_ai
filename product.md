# AI Hub 产品设计文档

## 核心目标

**轻量、快速、纯外壳** —— 利用 Tauri 2.0 + Rust 的性能优势，打造流畅的 AI 聚合体验。

---

## 性能原则 (Performance Principles)

### 绝不卡顿

| 原则 | 说明 |
|------|------|
| **主线程只做 UI** | 主线程只负责 UI 响应和事件派发，绝不等待网络或 Webview 加载 |
| **异步优先** | 所有耗时操作使用 Rust 异步运行时，立即返回，后台处理 |
| **瞬间切换** | Webview 的 show/hide 是瞬间完成的，不重新加载 |
| **资源正确释放** | 关闭 Webview 时正确清理资源，确保能重新打开 |

### Rust 特性利用

```
┌──────────────────────────────────────────────────┐
│                    主线程                         │
│  只负责：UI 响应、事件派发                         │
│  绝不：等待网络、等待 Webview 加载                 │
└──────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│               Tauri 异步运行时                    │
│  Webview 创建、网页加载、数据持久化               │
│  完成后通过事件通知主线程                         │
└──────────────────────────────────────────────────┘
```

---

## 浏览器一致性原则 (Browser Consistency)

### 核心目标

**与真实浏览器访问体验完全一致**，网站无法检测到这是一个 WebView 容器。

### 需要解决的问题

| 问题 | 说明 | 解决方案 |
|------|------|----------|
| **User-Agent 检测** | 网站通过 UA 判断是否为真实浏览器 | 使用最新 Chrome UA，与系统浏览器一致 |
| **WebDriver 检测** | `navigator.webdriver` 为 true 会被识别 | 注入 JS 将其设为 undefined |
| **插件检测** | 真实浏览器有 plugins 数组 | 注入伪造的 plugins 信息 |
| **Cookie 丢失** | WebView Cookie 管理不当导致登录状态丢失 | 独立 data_directory + 正确的存储配置 |
| **Session 隔离** | 不同站点数据混乱 | 每个站点完全独立的存储目录 |

### 注入脚本 (Anti-Detection)

在每个 Webview 加载前注入以下脚本，消除 WebView 特征：

```javascript
// 消除 webdriver 检测
Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined
});

// 伪造 plugins（真实浏览器有 PDF 插件等）
Object.defineProperty(navigator, 'plugins', {
    get: () => [
        { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer' },
        { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai' },
        { name: 'Native Client', filename: 'internal-nacl-plugin' }
    ]
});

// 伪造 languages
Object.defineProperty(navigator, 'languages', {
    get: () => ['zh-CN', 'zh', 'en-US', 'en']
});

// 伪造 platform
Object.defineProperty(navigator, 'platform', {
    get: () => 'Win32'
});
```

### Webview 配置要求

```rust
WebviewBuilder::new()
    // 与真实 Chrome 一致的 UA
    .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    // 独立数据目录，保证 Cookie 持久化
    .data_directory(get_site_data_dir(site_id))
    // 加载前注入反检测脚本
    .initialization_script(ANTI_DETECTION_SCRIPT)
    // 启用必要功能
    .auto_resize()
```

### 数据持久化目录结构

```
~/.local/share/ai-hub/          # Linux
~/Library/Application Support/ai-hub/  # macOS
%APPDATA%/ai-hub/               # Windows

└── webviews/
    ├── deepseek/
    │   ├── cookies
    │   ├── localStorage
    │   └── indexedDB/
    └── doubao/
        ├── cookies
        ├── localStorage
        └── indexedDB/
```

---

## 1. 核心视图管理设计 (The Multi-View Engine)

采用 Tauri 2.0 的 **Multi-Webview** 架构，使用 `WebviewBuilder` + `add_child()` 嵌入式方案。

### 架构图

```
┌─────────────────────────────────────────┐
│ 主窗口 (main window)                     │
│ ┌──────┬──────────────────────────────┐ │
│ │侧边栏│    嵌入式 Webview            │ │
│ │ Vue  │    (DeepSeek/豆包)           │ │
│ │64px  │                              │ │
│ │      │    完全填充右侧区域           │ │
│ │      │                              │ │
│ └──────┴──────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 视图持久化 (Session Persistence)

每个 AI 站点分配独立的 `data_directory`：
- **效果：** 软件关闭后，登录状态和 Cookie 不会丢失
- **隔离：** 不同站点的数据完全隔离，互不影响

### 视图切换逻辑

1. 前端点击导航按钮，调用 `invoke("switch_view", { siteId })`
2. Rust 后端异步处理：隐藏当前 webview，显示目标 webview
3. **瞬间完成**，网页在后台保持运行，无需重新加载

---

## 2. 站点配置

### 预设站点列表

| 站点 | URL | 图标 |
|------|-----|------|
| **DeepSeek** | `https://chat.deepseek.com` | deepseek |
| **豆包** | `https://www.doubao.com/chat/` | doubao |

### 后续可扩展

- ChatGPT (`https://chatgpt.com`)
- Claude (`https://claude.ai`)
- Gemini (`https://gemini.google.com`)

---

## 3. 侧边导航栏设计

### 布局

- **宽度：** 固定 64px
- **背景：** 深色 (#1e1e2e)
- **图标尺寸：** 24x24px，点击区域 48x48px

### 交互

- **点击：** 切换到对应 AI 站点
- **右键菜单：**
  - 刷新页面
  - 清除缓存
  - 打开开发者工具

### 状态指示

- **选中状态：** 左侧显示 4px 宽的强调色条
- **悬停状态：** 背景色变亮

---

## 4. 关键配置参数

| 模块 | 配置项 | 值 |
|------|--------|-----|
| **Window** | 默认尺寸 | 1200 x 800 |
| **Window** | 最小尺寸 | 800 x 600 |
| **Window** | resizable | true |
| **Sidebar** | 宽度 | 64px |
| **Webview** | user_agent | `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36` |
| **Webview** | 位置 | x: 64px, y: 0 |
| **Webview** | 尺寸 | 窗口宽度-64px, 窗口高度 |

---

## 5. 交互流程

1. **启动：** 软件开启，显示侧边栏和欢迎页面
2. **选择：** 用户点击 DeepSeek 图标，异步创建 Webview 并显示
3. **登录：** 用户在 Webview 中登录，Cookie 自动保存
4. **切换：** 点击豆包图标，瞬间切换（hide/show）
5. **关闭：** 关闭窗口时，正确释放所有 Webview 资源

---

## 6. 技术实现要点

### 异步 Webview 创建

```rust
#[tauri::command]
async fn switch_view(app: AppHandle, site_id: String) -> Result<(), String> {
    // 1. 隐藏当前 webview（瞬间）
    // 2. 检查目标 webview 是否存在
    // 3. 不存在则异步创建，立即返回
    // 4. 存在则直接显示
    Ok(())
}
```

### Webview 尺寸自适应

```rust
// 监听窗口 resize 事件
window.on_window_event(|event| {
    if let WindowEvent::Resized(_) = event {
        // 更新所有 webview 的 bounds
    }
});
```

### 状态管理

使用 `tokio::sync::Mutex` 而非 `std::sync::Mutex`，避免死锁：

```rust
use tokio::sync::Mutex;

static VIEWS: Lazy<Mutex<HashMap<String, bool>>> = Lazy::new(|| Mutex::new(HashMap::new()));
```

---

## 7. 文件结构

```
tauri-app/
├── src/                    # Vue 前端
│   ├── App.vue            # 主组件（侧边栏）
│   └── main.ts            # 入口
├── src-tauri/
│   ├── src/
│   │   ├── lib.rs         # 核心逻辑
│   │   └── main.rs        # 入口
│   ├── Cargo.toml         # Rust 依赖
│   └── tauri.conf.json    # Tauri 配置
└── package.json           # 前端依赖
```

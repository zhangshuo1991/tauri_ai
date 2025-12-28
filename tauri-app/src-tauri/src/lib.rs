use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::path::PathBuf;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use tauri::{
    webview::{PageLoadEvent, WebviewBuilder},
    Manager, Emitter, WebviewUrl, LogicalPosition, LogicalSize,
};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};
use tokio::sync::oneshot;

// ============================================================================
// 常量配置
// ============================================================================

/// Chrome User Agent - 与真实浏览器一致
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

/// 反检测脚本 - 在页面加载前注入，消除 WebView 特征
const ANTI_DETECTION_SCRIPT: &str = r#"
// 消除 webdriver 检测
Object.defineProperty(navigator, 'webdriver', {
    get: () => undefined
});

// 伪造 plugins（真实浏览器有 PDF 插件等）
Object.defineProperty(navigator, 'plugins', {
    get: () => {
        const plugins = [
            { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
            { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
            { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
        ];
        plugins.item = (i) => plugins[i];
        plugins.namedItem = (name) => plugins.find(p => p.name === name);
        plugins.refresh = () => {};
        return plugins;
    }
});

// 伪造 languages
Object.defineProperty(navigator, 'languages', {
    get: () => ['zh-CN', 'zh', 'en-US', 'en']
});

// 伪造 platform
Object.defineProperty(navigator, 'platform', {
    get: () => 'Win32'
});

// 伪造 vendor
Object.defineProperty(navigator, 'vendor', {
    get: () => 'Google Inc.'
});

// 消除 automation 检测
delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;

// 伪造 chrome 对象
window.chrome = {
    runtime: {},
    loadTimes: function() {},
    csi: function() {},
    app: {}
};
"#;

// ============================================================================
// 数据结构
// ============================================================================

/// AI 站点配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiSite {
    pub id: String,
    pub name: String,
    pub url: String,
    pub icon: String,
    #[serde(default)]
    pub builtin: bool,
    #[serde(default)]
    pub summary_prompt_override: String,
}

/// 应用配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub sites: Vec<AiSite>,
    pub site_order: Vec<String>,
    #[serde(default)]
    pub pinned_site_ids: Vec<String>,
    #[serde(default)]
    pub recent_site_ids: Vec<String>,
    pub theme: String,
    pub sidebar_width: f64,
    #[serde(default = "default_sidebar_expanded_width")]
    pub sidebar_expanded_width: f64,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default = "default_summary_prompt_template")]
    pub summary_prompt_template: String,
    #[serde(default)]
    pub ai_api_base_url: String,
    #[serde(default)]
    pub ai_api_model: String,
    #[serde(default)]
    pub ai_api_key: String,
    #[serde(default)]
    pub active_project_id: String,
}

fn default_sidebar_expanded_width() -> f64 {
    180.0
}

fn default_language() -> String {
    "zh-CN".to_string()
}

fn default_summary_prompt_template() -> String {
    // Variables:
    // - {language}: desired output language label
    // - {text}: extracted page text
    "请把以下内容总结成可迁移的上下文（输出语言：{language}）：\n\n要求：\n1) 1段简短摘要（<=120字）\n2) 5-10条要点列表\n3) 关键约束/偏好（如有）\n\n输出为纯文本，结构：\n摘要: ...\n要点: - ...\n约束: - ...\n\n内容：\n{text}".to_string()
}

impl Default for AppConfig {
    fn default() -> Self {
        let default_sites = get_builtin_sites();
        let site_order: Vec<String> = default_sites.iter().map(|s| s.id.clone()).collect();
        Self {
            sites: default_sites,
            site_order,
            pinned_site_ids: Vec::new(),
            recent_site_ids: Vec::new(),
            theme: "dark".to_string(),
            sidebar_width: 64.0,
            sidebar_expanded_width: default_sidebar_expanded_width(),
            language: default_language(),
            summary_prompt_template: default_summary_prompt_template(),
            ai_api_base_url: "https://api.openai.com/v1".to_string(),
            ai_api_model: "".to_string(),
            ai_api_key: "".to_string(),
            active_project_id: "".to_string(),
        }
    }
}

/// 获取内置站点列表
fn get_builtin_sites() -> Vec<AiSite> {
    vec![
        AiSite {
            id: "deepseek".to_string(),
            name: "DeepSeek".to_string(),
            url: "https://chat.deepseek.com".to_string(),
            icon: "deepseek".to_string(),
            builtin: true,
            summary_prompt_override: String::new(),
        },
        AiSite {
            id: "doubao".to_string(),
            name: "豆包".to_string(),
            url: "https://www.doubao.com/chat/".to_string(),
            icon: "doubao".to_string(),
            builtin: true,
            summary_prompt_override: String::new(),
        },
        AiSite {
            id: "openai".to_string(),
            name: "ChatGPT".to_string(),
            url: "https://chatgpt.com".to_string(),
            icon: "openai".to_string(),
            builtin: true,
            summary_prompt_override: String::new(),
        },
        AiSite {
            id: "qianwen".to_string(),
            name: "通义千问".to_string(),
            url: "https://tongyi.aliyun.com/qianwen/".to_string(),
            icon: "qianwen".to_string(),
            builtin: true,
            summary_prompt_override: String::new(),
        },
    ]
}

// ============================================================================
// 配置文件管理
// ============================================================================

/// 获取配置文件路径
fn get_config_path() -> PathBuf {
    let proj_dirs = directories::ProjectDirs::from("com", "aihub", "AIHub")
        .expect("Could not get project directories");
    let config_dir = proj_dirs.config_dir();
    let _ = fs::create_dir_all(config_dir);
    config_dir.join("config.json")
}

fn get_contexts_path() -> PathBuf {
    let proj_dirs = directories::ProjectDirs::from("com", "aihub", "AIHub")
        .expect("Could not get project directories");
    let config_dir = proj_dirs.config_dir();
    let _ = fs::create_dir_all(config_dir);
    config_dir.join("contexts.json")
}

/// 加载配置
fn load_config() -> AppConfig {
    let config_path = get_config_path();

    if config_path.exists() {
        match fs::read_to_string(&config_path) {
            Ok(content) => {
                match serde_json::from_str::<AppConfig>(&content) {
                    Ok(mut config) => {
                        // 去重 sites（避免历史 bug 导致重复站点）
                        let mut seen_sites: HashSet<String> = HashSet::new();
                        config.sites.retain(|s| seen_sites.insert(s.id.clone()));

                        // 确保内置站点存在
                        let builtin_sites = get_builtin_sites();
                        for builtin in &builtin_sites {
                            if !config.sites.iter().any(|s| s.id == builtin.id) {
                                config.sites.push(builtin.clone());
                                config.site_order.push(builtin.id.clone());
                            }
                        }

                        // 清理 site_order / pinned / recent 中不存在的站点，并去重保持顺序
                        let existing_ids: HashSet<String> =
                            config.sites.iter().map(|s| s.id.clone()).collect();

                        // 站点顺序：去重、移除不存在项，并补齐遗漏的站点
                        let mut next_order: Vec<String> = Vec::new();
                        let mut seen_order: HashSet<String> = HashSet::new();
                        for id in &config.site_order {
                            if !existing_ids.contains(id) {
                                continue;
                            }
                            if !seen_order.insert(id.clone()) {
                                continue;
                            }
                            next_order.push(id.clone());
                        }
                        for site in &config.sites {
                            if seen_order.insert(site.id.clone()) {
                                next_order.push(site.id.clone());
                            }
                        }
                        config.site_order = next_order;

                        // 侧边栏展开宽度：迁移旧配置
                        const MIN_SIDEBAR_WIDTH: f64 = 64.0;
                        if config.sidebar_width > MIN_SIDEBAR_WIDTH
                            && config.sidebar_expanded_width <= MIN_SIDEBAR_WIDTH
                        {
                            config.sidebar_expanded_width = config.sidebar_width;
                        }

                        // 迁移 AI API base_url：若为空则使用默认
                        if config.ai_api_base_url.trim().is_empty() {
                            config.ai_api_base_url = "https://api.openai.com/v1".to_string();
                        }

                        let mut seen = std::collections::HashSet::<String>::new();
                        config.pinned_site_ids.retain(|id| {
                            if !existing_ids.contains(id) {
                                return false;
                            }
                            if seen.contains(id) {
                                return false;
                            }
                            seen.insert(id.clone());
                            true
                        });

                        let mut seen_recent = std::collections::HashSet::<String>::new();
                        config.recent_site_ids.retain(|id| {
                            if !existing_ids.contains(id) {
                                return false;
                            }
                            if seen_recent.contains(id) {
                                return false;
                            }
                            seen_recent.insert(id.clone());
                            true
                        });

                        // 将清理/补齐后的配置写回，避免重复脏数据导致 UI 重复
                        let _ = save_config(&config);
                        return config;
                    }
                    Err(e) => {
                        println!("配置解析失败: {}, 使用默认配置", e);
                    }
                }
            }
            Err(e) => {
                println!("读取配置失败: {}, 使用默认配置", e);
            }
        }
    }

    // 返回默认配置并保存
    let config = AppConfig::default();
    let _ = save_config(&config);
    config
}

/// 保存配置
fn save_config(config: &AppConfig) -> Result<(), String> {
    let config_path = get_config_path();
    let content = serde_json::to_string_pretty(config)
        .map_err(|e| format!("序列化配置失败: {}", e))?;
    fs::write(&config_path, content)
        .map_err(|e| format!("写入配置失败: {}", e))?;
    Ok(())
}

// ============================================================================
// 全局状态（使用 Mutex 保证线程安全）
// ============================================================================

/// 应用配置
static APP_CONFIG: Lazy<Mutex<AppConfig>> = Lazy::new(|| Mutex::new(load_config()));

/// 当前显示的视图 ID
static CURRENT_VIEW: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

/// 已创建的 Webview 记录
static CREATED_VIEWS: Lazy<Mutex<HashMap<String, bool>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// 额外 Tab → 站点映射（主 Tab 使用 `tab_id == site_id`，不存这里）
static TAB_SITE_MAP: Lazy<Mutex<HashMap<String, String>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// 当前活跃 Tab（用于单视图模式）
static ACTIVE_TAB_ID: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::new()));

#[derive(Debug, Clone)]
enum LayoutMode {
    Single,
    Split,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProjectContext {
    id: String,
    title: String,
    notes: String,
    summary: String,
    created_at: u64,
    updated_at: u64,
}

#[derive(Debug, Clone, Serialize)]
struct ProjectSummary {
    id: String,
    title: String,
    updated_at: u64,
}

fn now_ts() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn load_contexts() -> Vec<ProjectContext> {
    let path = get_contexts_path();
    if !path.exists() {
        return Vec::new();
    }
    match fs::read_to_string(&path) {
        Ok(content) => serde_json::from_str::<Vec<ProjectContext>>(&content).unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}

fn save_contexts(contexts: &[ProjectContext]) -> Result<(), String> {
    let path = get_contexts_path();
    let content = serde_json::to_string_pretty(contexts)
        .map_err(|e| format!("序列化 contexts 失败: {}", e))?;
    fs::write(&path, content).map_err(|e| format!("写入 contexts 失败: {}", e))?;
    Ok(())
}

#[derive(Debug, Clone)]
struct LayoutState {
    mode: LayoutMode,
    ratio: f64,
    left_tab_id: Option<String>,
    right_tab_id: Option<String>,
}

impl Default for LayoutState {
    fn default() -> Self {
        Self {
            mode: LayoutMode::Single,
            ratio: 0.5,
            left_tab_id: None,
            right_tab_id: None,
        }
    }
}

static LAYOUT_STATE: Lazy<Mutex<LayoutState>> = Lazy::new(|| Mutex::new(LayoutState::default()));

const TOP_BAR_HEIGHT: f64 = 48.0;

/// 避免在创建 Webview 时处理 Resized 事件导致的潜在死锁
static WEBVIEW_CREATE_IN_PROGRESS: AtomicUsize = AtomicUsize::new(0);
static SUMMARY_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

#[derive(Debug)]
struct PendingExtract {
    token: String,
    tx: oneshot::Sender<String>,
}

static PENDING_EXTRACTS: Lazy<Mutex<HashMap<String, PendingExtract>>> =
    Lazy::new(|| Mutex::new(HashMap::new()));

fn is_main_invoker_webview(webview: &tauri::Webview) -> bool {
    webview.label() == "main"
}

fn language_label(code: &str) -> &'static str {
    match code {
        "zh-CN" | "zh" => "中文",
        "en" | "en-US" | "en-GB" => "English",
        "ja" | "ja-JP" => "日本語",
        "ko" | "ko-KR" => "한국어",
        "es" | "es-ES" | "es-AR" => "Español",
        "fr" | "fr-FR" => "Français",
        _ => "English",
    }
}

fn build_summary_prompt(template: &str, language: &str, text: &str) -> String {
    let mut rendered = template
        .replace("{language}", language)
        .replace("{text}", text);
    if !template.contains("{language}") {
        rendered.push_str("\n\nLanguage: ");
        rendered.push_str(language);
    }
    if !template.contains("{text}") {
        rendered.push_str("\n\n");
        rendered.push_str(text);
    }
    rendered
}

// ============================================================================
// 工具函数
// ============================================================================

/// 获取站点数据目录（用于 Cookie 持久化）
fn get_data_dir(site_id: &str) -> std::path::PathBuf {
    let proj_dirs = directories::ProjectDirs::from("com", "aihub", "AIHub")
        .expect("Could not get project directories");
    proj_dirs.data_dir().join("webviews").join(site_id)
}

/// 获取 Tab 对应的数据目录
/// - 主 Tab（tab_id == site_id）使用站点目录（兼容已有数据）
/// - 额外 Tab 使用独立目录，避免多个 WebView2 实例同时占用同一 profile 目录导致卡死
fn get_tab_data_dir(site_id: &str, tab_id: &str) -> std::path::PathBuf {
    if tab_id == site_id {
        return get_data_dir(site_id);
    }
    // 注意：避免把一个 profile 目录嵌套在另一个 profile 目录内（Windows WebView2 可能会卡住）
    let proj_dirs = directories::ProjectDirs::from("com", "aihub", "AIHub")
        .expect("Could not get project directories");
    proj_dirs
        .data_dir()
        .join("webviews_tabs")
        .join(site_id)
        .join(tab_id)
}

/// 计算 Webview 的位置和尺寸
fn calculate_webview_bounds(window: &tauri::Window) -> (LogicalPosition<f64>, LogicalSize<f64>) {
    let size = window.inner_size().unwrap_or_default();
    let scale = window.scale_factor().unwrap_or(1.0);

    // 获取动态侧边栏宽度
    let sidebar_width = APP_CONFIG.lock().unwrap().sidebar_width;

    // 转换为逻辑像素
    let window_width = size.width as f64 / scale;
    let window_height = size.height as f64 / scale;

    // Webview 位置：从侧边栏右侧开始，并避开顶部栏（chrome）
    let position = LogicalPosition::new(sidebar_width, TOP_BAR_HEIGHT);

    // Webview 尺寸：窗口宽度减去侧边栏，高度减去顶部栏
    let webview_width = (window_width - sidebar_width).max(100.0);
    let webview_height = (window_height - TOP_BAR_HEIGHT).max(100.0);
    let size = LogicalSize::new(webview_width, webview_height);

    (position, size)
}

fn get_main_window(app: &tauri::AppHandle) -> Result<tauri::Window, String> {
    if let Some(main_window) = app.get_webview_window("main") {
        Ok(main_window.as_ref().window().clone())
    } else if let Some(win) = app.get_window("main") {
        Ok(win)
    } else {
        Err("主窗口不存在".to_string())
    }
}

fn get_site_by_id(site_id: &str) -> Result<AiSite, String> {
    let config = APP_CONFIG.lock().unwrap();
    config
        .sites
        .iter()
        .find(|s| s.id == site_id)
        .cloned()
        .ok_or_else(|| format!("站点不存在: {}", site_id))
}

fn get_tab_site_id(tab_id: &str) -> Result<String, String> {
    // 主 Tab：tab_id == site_id
    if APP_CONFIG.lock().unwrap().sites.iter().any(|s| s.id == tab_id) {
        return Ok(tab_id.to_string());
    }

    TAB_SITE_MAP
        .lock()
        .unwrap()
        .get(tab_id)
        .cloned()
        .ok_or_else(|| "Tab 不存在".to_string())
}

fn upsert_recent_site(site_id: &str) {
    let mut config = APP_CONFIG.lock().unwrap();
    config.recent_site_ids.retain(|id| id != site_id);
    config.recent_site_ids.insert(0, site_id.to_string());
    config.recent_site_ids.truncate(10);
    let _ = save_config(&config);
}

fn ensure_tab_webview(app: &tauri::AppHandle, tab_id: &str, site_id: &str) -> Result<(), String> {
    let window = get_main_window(app)?;
    let (position, size) = calculate_webview_bounds(&window);
    let webview_label = format!("ai_{}", tab_id);

    println!(
        "[ensure_tab_webview] tab_id={} site_id={} label={}",
        tab_id, site_id, webview_label
    );

    let view_exists = CREATED_VIEWS.lock().unwrap().contains_key(tab_id);
    if view_exists {
        if let Some(webview) = app.get_webview(&webview_label) {
            let _ = webview.set_position(position);
            let _ = webview.set_size(size);
            return Ok(());
        }

        CREATED_VIEWS.lock().unwrap().remove(tab_id);
    }

    let site = get_site_by_id(site_id)?;
    let _ = app.emit("webview-loading", site_id);

    let data_dir = get_tab_data_dir(site_id, tab_id);
    println!("[ensure_tab_webview] data_dir={}", data_dir.display());
    let _ = std::fs::create_dir_all(&data_dir);

    let url: tauri::Url = site
        .url
        .parse()
        .map_err(|e| format!("URL 解析失败: {}", e))?;

    let app_handle = app.clone();
    let site_id_clone = site_id.to_string();

    let webview_builder = WebviewBuilder::new(&webview_label, WebviewUrl::External(url))
        .user_agent(USER_AGENT)
        .initialization_script(ANTI_DETECTION_SCRIPT)
        .data_directory(data_dir)
        .on_page_load(move |webview, payload| match payload.event() {
            PageLoadEvent::Started => {
                println!("[{}] 页面开始加载", webview.label());
            }
            PageLoadEvent::Finished => {
                println!("[{}] 页面加载完成", webview.label());
                let _ = app_handle.emit("webview-loaded", &site_id_clone);
            }
        });

    struct WebviewCreateGuard;
    impl Drop for WebviewCreateGuard {
        fn drop(&mut self) {
            WEBVIEW_CREATE_IN_PROGRESS.fetch_sub(1, Ordering::SeqCst);
        }
    }

    println!("[ensure_tab_webview] add_child start label={}", webview_label);
    WEBVIEW_CREATE_IN_PROGRESS.fetch_add(1, Ordering::SeqCst);
    let _guard = WebviewCreateGuard;
    window
        .add_child(
            webview_builder,
            LogicalPosition::new(position.x, position.y),
            LogicalSize::new(size.width, size.height),
        )
        .map_err(|e| format!("添加 Webview 失败: {}", e))?;
    println!("[ensure_tab_webview] add_child done label={}", webview_label);

    CREATED_VIEWS.lock().unwrap().insert(tab_id.to_string(), true);
    Ok(())
}

fn tab_ids_for_site(site_id: &str) -> Vec<String> {
    let mut ids: Vec<String> = vec![site_id.to_string()];
    for (tab_id, mapped_site) in TAB_SITE_MAP.lock().unwrap().iter() {
        if mapped_site == site_id {
            ids.push(tab_id.clone());
        }
    }
    ids
}

fn close_tab_webview(app: &tauri::AppHandle, tab_id: &str) {
    let webview_label = format!("ai_{}", tab_id);
    if let Some(webview) = app.get_webview(&webview_label) {
        let _ = webview.close();
    }
    CREATED_VIEWS.lock().unwrap().remove(tab_id);
    TAB_SITE_MAP.lock().unwrap().remove(tab_id);
}

fn first_site_id_excluding(exclude_site_id: &str) -> Option<String> {
    let config = APP_CONFIG.lock().unwrap();
    let existing: HashSet<String> = config.sites.iter().map(|s| s.id.clone()).collect();
    let mut seen: HashSet<String> = HashSet::new();

    for id in &config.pinned_site_ids {
        if !existing.contains(id) || id == exclude_site_id {
            continue;
        }
        if seen.insert(id.clone()) {
            return Some(id.clone());
        }
    }

    for id in &config.site_order {
        if !existing.contains(id) || id == exclude_site_id {
            continue;
        }
        if seen.insert(id.clone()) {
            return Some(id.clone());
        }
    }

    for site in &config.sites {
        if site.id == exclude_site_id {
            continue;
        }
        if seen.insert(site.id.clone()) {
            return Some(site.id.clone());
        }
    }

    None
}

// ============================================================================
// Tauri Commands
// ============================================================================

/// 获取应用配置
#[tauri::command]
fn get_config(webview: tauri::Webview) -> Result<AppConfig, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    // 注意：不要把 API Key 暴露给前端/远程页面
    let mut cfg = APP_CONFIG.lock().unwrap().clone();
    cfg.ai_api_key.clear();
    Ok(cfg)
}

#[tauri::command]
fn set_ai_api_settings(
    webview: tauri::Webview,
    base_url: String,
    model: String,
    api_key: String,
    clear_key: Option<bool>,
) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let base_url_trimmed = base_url.trim().trim_end_matches('/').to_string();
    let base_url = if base_url_trimmed.is_empty() {
        "https://api.openai.com/v1".to_string()
    } else {
        base_url_trimmed
    };
    let model = model.trim().to_string();

    let mut config = APP_CONFIG.lock().unwrap();
    config.ai_api_base_url = base_url;
    config.ai_api_model = model;
    let api_key_trimmed = api_key.trim().to_string();
    if !api_key_trimmed.is_empty() || clear_key == Some(true) {
        config.ai_api_key = api_key_trimmed;
    }
    save_config(&config)?;
    Ok(())
}

#[tauri::command]
fn set_active_project(webview: tauri::Webview, project_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    config.active_project_id = project_id;
    save_config(&config)?;
    Ok(())
}

#[tauri::command]
fn set_language(webview: tauri::Webview, language: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let lang = language.trim().to_string();
    if lang.is_empty() {
        return Err("language 不能为空".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    config.language = lang;
    save_config(&config)?;
    Ok(())
}

#[tauri::command]
fn set_summary_prompt_template(webview: tauri::Webview, template: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let trimmed = template.trim().to_string();
    let mut config = APP_CONFIG.lock().unwrap();
    config.summary_prompt_template = if trimmed.is_empty() {
        default_summary_prompt_template()
    } else {
        trimmed
    };
    save_config(&config)?;
    Ok(())
}

#[tauri::command]
fn list_projects(webview: tauri::Webview) -> Result<Vec<ProjectSummary>, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut projects = load_contexts();
    projects.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    Ok(projects
        .into_iter()
        .map(|p| ProjectSummary {
            id: p.id,
            title: p.title,
            updated_at: p.updated_at,
        })
        .collect())
}

#[tauri::command]
fn get_project(webview: tauri::Webview, project_id: String) -> Result<ProjectContext, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let projects = load_contexts();
    projects
        .into_iter()
        .find(|p| p.id == project_id)
        .ok_or_else(|| "项目不存在".to_string())
}

#[tauri::command]
fn create_project(webview: tauri::Webview, title: String) -> Result<String, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut projects = load_contexts();
    let id = format!("proj_{}", Uuid::new_v4().to_string().split('-').next().unwrap());
    let ts = now_ts();
    projects.push(ProjectContext {
        id: id.clone(),
        title: if title.trim().is_empty() {
            "默认项目".to_string()
        } else {
            title.trim().to_string()
        },
        notes: String::new(),
        summary: String::new(),
        created_at: ts,
        updated_at: ts,
    });
    save_contexts(&projects)?;

    let mut config = APP_CONFIG.lock().unwrap();
    config.active_project_id = id.clone();
    let _ = save_config(&config);

    Ok(id)
}

#[tauri::command]
fn update_project(
    webview: tauri::Webview,
    project_id: String,
    title: String,
    notes: String,
    summary: String,
) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut projects = load_contexts();
    let mut found = false;
    for p in projects.iter_mut() {
        if p.id != project_id {
            continue;
        }
        found = true;
        p.title = if title.trim().is_empty() { p.title.clone() } else { title.trim().to_string() };
        p.notes = notes;
        p.summary = summary;
        p.updated_at = now_ts();
        break;
    }
    if !found {
        return Err("项目不存在".to_string());
    }
    save_contexts(&projects)?;
    Ok(())
}

#[tauri::command]
fn delete_project(webview: tauri::Webview, project_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut projects = load_contexts();
    let before = projects.len();
    projects.retain(|p| p.id != project_id);
    if projects.len() == before {
        return Err("项目不存在".to_string());
    }
    save_contexts(&projects)?;

    let mut config = APP_CONFIG.lock().unwrap();
    if config.active_project_id == project_id {
        config.active_project_id = String::new();
        let _ = save_config(&config);
    }
    Ok(())
}

#[derive(Debug, Clone, Deserialize)]
struct OpenAiChatResponse {
    choices: Vec<OpenAiChoice>,
}

#[derive(Debug, Clone, Deserialize)]
struct OpenAiChoice {
    message: OpenAiMessage,
}

#[derive(Debug, Clone, Deserialize)]
struct OpenAiMessage {
    content: String,
}

#[tauri::command]
async fn summarize_text(webview: tauri::Webview, text: String, site_id: Option<String>) -> Result<String, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let config = APP_CONFIG.lock().unwrap().clone();
    if config.ai_api_key.trim().is_empty() {
        return Err("未配置 API Key".to_string());
    }
    if config.ai_api_model.trim().is_empty() {
        return Err("未配置 Model".to_string());
    }

    let base_url = config.ai_api_base_url.trim().trim_end_matches('/').to_string();
    let url = format!("{}/chat/completions", base_url);

    let mut template = config.summary_prompt_template.clone();
    if let Some(id) = site_id.as_deref() {
        if let Some(site) = config.sites.iter().find(|s| s.id == id) {
            if !site.summary_prompt_override.trim().is_empty() {
                template = site.summary_prompt_override.clone();
            }
        }
    }
    if template.trim().is_empty() {
        template = default_summary_prompt_template();
    }
    let prompt = build_summary_prompt(&template, language_label(&config.language), &text);

    let body = serde_json::json!({
        "model": config.ai_api_model,
        "messages": [
            { "role": "system", "content": "你是一个擅长提炼上下文与约束的助手。" },
            { "role": "user", "content": prompt }
        ],
        "temperature": 0.2
    });

    let client = reqwest::Client::new();
    let resp = client
        .post(url)
        .header(CONTENT_TYPE, "application/json")
        .header(AUTHORIZATION, format!("Bearer {}", config.ai_api_key))
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("请求失败: {}", e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!("API 返回错误 {}: {}", status, text));
    }

    let data = resp
        .json::<OpenAiChatResponse>()
        .await
        .map_err(|e| format!("解析响应失败: {}", e))?;

    let content = data
        .choices
        .get(0)
        .map(|c| c.message.content.clone())
        .unwrap_or_default();

    if content.trim().is_empty() {
        return Err("API 返回空内容".to_string());
    }

    Ok(content)
}

fn ensure_active_project_id() -> Result<String, String> {
    let mut config = APP_CONFIG.lock().unwrap();
    if !config.active_project_id.trim().is_empty() {
        return Ok(config.active_project_id.clone());
    }

    let mut projects = load_contexts();
    if let Some(first) = projects.first() {
        config.active_project_id = first.id.clone();
        let _ = save_config(&config);
        return Ok(first.id.clone());
    }

    let id = format!("proj_{}", Uuid::new_v4().to_string().split('-').next().unwrap());
    let ts = now_ts();
    projects.push(ProjectContext {
        id: id.clone(),
        title: "默认项目".to_string(),
        notes: String::new(),
        summary: String::new(),
        created_at: ts,
        updated_at: ts,
    });
    save_contexts(&projects)?;

    config.active_project_id = id.clone();
    let _ = save_config(&config);
    Ok(id)
}

#[tauri::command]
async fn aihub_submit_page_text(request_id: String, token: String, text: String) -> Result<(), String> {
    let pending = PENDING_EXTRACTS.lock().unwrap().remove(&request_id);
    if let Some(p) = pending {
        if p.token != token {
            return Ok(());
        }
        let _ = p.tx.send(text);
    }
    Ok(())
}

/// 标记“当前活跃 Tab”（用于 split 模式下的“总结当前对话”）
#[tauri::command]
fn set_active_tab_id(webview: tauri::Webview, tab_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    if tab_id.trim().is_empty() {
        return Ok(());
    }
    *ACTIVE_TAB_ID.lock().unwrap() = tab_id;
    Ok(())
}

#[tauri::command]
async fn summarize_active_tab(app: tauri::AppHandle, webview: tauri::Webview) -> Result<String, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }

    if SUMMARY_IN_PROGRESS
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("总结正在进行中，请稍候…".to_string());
    }

    struct SummaryInProgressGuard;
    impl Drop for SummaryInProgressGuard {
        fn drop(&mut self) {
            SUMMARY_IN_PROGRESS.store(false, Ordering::SeqCst);
        }
    }
    let _guard = SummaryInProgressGuard;

    let result = tokio::time::timeout(
        std::time::Duration::from_secs(60),
        async {
    let tab_id = {
        let active = ACTIVE_TAB_ID.lock().unwrap().clone();
        if !active.is_empty() {
            active
        } else {
            CURRENT_VIEW.lock().unwrap().clone()
        }
    };

    if tab_id.trim().is_empty() {
        return Err("没有可总结的页面".to_string());
    }

    let site_id = get_tab_site_id(&tab_id).unwrap_or_else(|_| tab_id.clone());
    ensure_tab_webview(&app, &tab_id, &site_id)?;

    let webview_label = format!("ai_{}", tab_id);
    let child = app
        .get_webview(&webview_label)
        .ok_or_else(|| "Webview 不存在".to_string())?;

    let request_id = Uuid::new_v4().to_string();
    let token = Uuid::new_v4().to_string();
    let (tx, rx) = oneshot::channel::<String>();
    PENDING_EXTRACTS
        .lock()
        .unwrap()
        .insert(request_id.clone(), PendingExtract { token: token.clone(), tx });

    let js = format!(
        r#"(async () => {{
  try {{
    const text = document?.body?.innerText || '';
    await window.__TAURI__.core.invoke('aihub_submit_page_text', {{ requestId: '{rid}', token: '{tok}', text }});
  }} catch (e) {{
    try {{
      await window.__TAURI__.core.invoke('aihub_submit_page_text', {{ requestId: '{rid}', token: '{tok}', text: '' }});
    }} catch (_) {{}}
  }}
}})();"#,
        rid = request_id,
        tok = token
    );

    child.eval(&js).map_err(|e| format!("执行提取脚本失败: {}", e))?;

    let extracted = match tokio::time::timeout(std::time::Duration::from_secs(20), rx).await {
        Ok(res) => res.map_err(|_| "提取失败".to_string())?,
        Err(_) => {
            PENDING_EXTRACTS.lock().unwrap().remove(&request_id);
            return Err("提取超时".to_string());
        }
    };

    if extracted.trim().is_empty() {
        return Err("未能提取到页面文本（可能被站点限制或页面未加载完成）".to_string());
    }

    // 总结（内部调用，避免再次经过 invoke 参数校验）
    let summary = summarize_text(webview, extracted.clone(), Some(site_id.clone())).await?;

    // 保存到 active project（覆盖 notes/summary）
    let project_id = ensure_active_project_id()?;
    let mut projects = load_contexts();
    let ts = now_ts();
    let mut found = false;
    for p in projects.iter_mut() {
        if p.id != project_id {
            continue;
        }
        found = true;
        p.notes = extracted;
        p.summary = summary.clone();
        p.updated_at = ts;
        break;
    }
    if !found {
        projects.push(ProjectContext {
            id: project_id,
            title: "默认项目".to_string(),
            notes: String::new(),
            summary: summary.clone(),
            created_at: ts,
            updated_at: ts,
        });
    }
    let _ = save_contexts(&projects);

    Ok(summary)
        },
    )
    .await;

    match result {
        Ok(res) => res,
        Err(_) => Err("总结超时（60s）".to_string()),
    }
}

/// 获取所有 AI 站点列表（按排序顺序）
#[tauri::command]
fn get_ai_sites(webview: tauri::Webview) -> Result<Vec<AiSite>, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let config = APP_CONFIG.lock().unwrap();
    let mut sites: Vec<AiSite> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();

    // 按 site_order 排序
    for id in &config.site_order {
        if !seen.insert(id.clone()) {
            continue;
        }
        if let Some(site) = config.sites.iter().find(|s| &s.id == id) {
            sites.push(site.clone());
        }
    }

    // 添加不在 order 中的站点
    for site in &config.sites {
        if seen.insert(site.id.clone()) {
            sites.push(site.clone());
        }
    }

    Ok(sites)
}

/// 获取当前活跃的视图 ID
#[tauri::command]
fn get_current_view(webview: tauri::Webview) -> Result<String, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    Ok(CURRENT_VIEW.lock().unwrap().clone())
}

#[derive(Debug, Clone, Serialize)]
struct TabInfo {
    tab_id: String,
    site_id: String,
}

#[derive(Debug, Clone, Serialize)]
struct TabsStateResponse {
    active_tab_id: String,
    mode: String,
    ratio: f64,
    left_tab_id: Option<String>,
    right_tab_id: Option<String>,
    tabs: Vec<TabInfo>,
}

/// 获取当前 Tabs 状态（用于前端渲染 TabBar/分屏）
#[tauri::command]
fn get_tabs_state(webview: tauri::Webview) -> Result<TabsStateResponse, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let layout = LAYOUT_STATE.lock().unwrap().clone();
    let active_tab_id = ACTIVE_TAB_ID.lock().unwrap().clone();

    let mut tab_ids: std::collections::HashSet<String> = CREATED_VIEWS.lock().unwrap().keys().cloned().collect();
    tab_ids.extend(TAB_SITE_MAP.lock().unwrap().keys().cloned());
    let current_site = CURRENT_VIEW.lock().unwrap().clone();
    if !current_site.is_empty() {
        tab_ids.insert(current_site);
    }

    let mut tabs: Vec<TabInfo> = Vec::new();
    for tab_id in tab_ids {
        if let Ok(site_id) = get_tab_site_id(&tab_id) {
            tabs.push(TabInfo { tab_id, site_id });
        }
    }
    tabs.sort_by(|a, b| a.tab_id.cmp(&b.tab_id));

    Ok(TabsStateResponse {
        active_tab_id,
        mode: match layout.mode {
            LayoutMode::Single => "single".to_string(),
            LayoutMode::Split => "split".to_string(),
        },
        ratio: layout.ratio,
        left_tab_id: layout.left_tab_id,
        right_tab_id: layout.right_tab_id,
        tabs,
    })
}

/// 创建一个新 Tab（默认共享站点登录：同站点共用 data directory）
#[tauri::command]
fn create_tab(webview: tauri::Webview, site_id: String) -> Result<String, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let _ = get_site_by_id(&site_id)?;
    println!("[create_tab] site_id={}", site_id);
    let tab_id = format!(
        "{}_{}",
        site_id,
        Uuid::new_v4().to_string().split('-').next().unwrap()
    );
    TAB_SITE_MAP.lock().unwrap().insert(tab_id.clone(), site_id);
    Ok(tab_id)
}

/// 切换到指定 Tab（进入单视图模式）
async fn switch_tab_inner(app: tauri::AppHandle, tab_id: String) -> Result<(), String> {
    let site_id = get_tab_site_id(&tab_id)?;
    println!("[switch_tab] tab_id={} site_id={}", tab_id, site_id);

    {
        let mut layout = LAYOUT_STATE.lock().unwrap();
        layout.mode = LayoutMode::Single;
        layout.left_tab_id = None;
        layout.right_tab_id = None;
    }

    *ACTIVE_TAB_ID.lock().unwrap() = tab_id.clone();
    ensure_tab_webview(&app, &tab_id, &site_id)?;
    resize_webviews_inner(&app, true)?;

    *CURRENT_VIEW.lock().unwrap() = site_id.clone();
    upsert_recent_site(&site_id);
    Ok(())
}

#[tauri::command]
async fn switch_tab(webview: tauri::Webview, app: tauri::AppHandle, tab_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    switch_tab_inner(app, tab_id).await
}

/// 设置布局（single/split）
#[tauri::command]
async fn set_layout(
    webview: tauri::Webview,
    app: tauri::AppHandle,
    mode: String,
    ratio: Option<f64>,
    left_tab_id: Option<String>,
    right_tab_id: Option<String>,
) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    if mode == "single" {
        println!("[set_layout] mode=single");
        {
            let mut layout = LAYOUT_STATE.lock().unwrap();
            layout.mode = LayoutMode::Single;
            layout.left_tab_id = None;
            layout.right_tab_id = None;
        }
        resize_webviews_inner(&app, true)?;
        return Ok(());
    }

    if mode != "split" {
        return Err("mode 仅支持 single|split".to_string());
    }

    let left = left_tab_id.ok_or_else(|| "缺少 left_tab_id".to_string())?;
    let right = right_tab_id.ok_or_else(|| "缺少 right_tab_id".to_string())?;
    println!("[set_layout] mode=split left={} right={}", left, right);
    if left == right {
        return Err("左右 Tab 不能相同".to_string());
    }

    // 不要在创建/添加 Webview 时持有 LAYOUT_STATE 锁，避免与 WindowEvent::Resized 产生死锁
    let desired_ratio = {
        let layout = LAYOUT_STATE.lock().unwrap();
        ratio.unwrap_or(layout.ratio).clamp(0.2, 0.8)
    };

    let left_site = get_tab_site_id(&left)?;
    let right_site = get_tab_site_id(&right)?;

    ensure_tab_webview(&app, &left, &left_site)?;
    ensure_tab_webview(&app, &right, &right_site)?;

    {
        let mut layout = LAYOUT_STATE.lock().unwrap();
        layout.mode = LayoutMode::Split;
        layout.ratio = desired_ratio;
        layout.left_tab_id = Some(left.clone());
        layout.right_tab_id = Some(right.clone());
    }

    resize_webviews_inner(&app, true)?;

    // 兼容：CURRENT_VIEW 仍返回“当前主站点”，优先 active tab 的站点
    if let Ok(active_site) = get_tab_site_id(&ACTIVE_TAB_ID.lock().unwrap().clone()) {
        *CURRENT_VIEW.lock().unwrap() = active_site;
    } else if let Ok(site) = get_tab_site_id(&left) {
        *CURRENT_VIEW.lock().unwrap() = site;
    }

    Ok(())
}

/// 关闭一个 Tab
#[tauri::command]
async fn close_tab(webview: tauri::Webview, app: tauri::AppHandle, tab_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let closed_site_id = get_tab_site_id(&tab_id).unwrap_or_else(|_| tab_id.clone());
    let webview_label = format!("ai_{}", tab_id);
    if let Some(webview) = app.get_webview(&webview_label) {
        let _ = webview.close();
    }

    CREATED_VIEWS.lock().unwrap().remove(&tab_id);
    TAB_SITE_MAP.lock().unwrap().remove(&tab_id);

    // 注意：不要在 await 时持有 MutexGuard（否则 future 非 Send）
    #[derive(Debug)]
    enum CloseFallback {
        None,
        SwitchToTab(String),
        SwitchToFirstSite(String),
        ClearToEmpty,
    }

    let fallback = {
        let mut layout = LAYOUT_STATE.lock().unwrap();
        match layout.mode {
            LayoutMode::Single => {
                let active_tab_id = ACTIVE_TAB_ID.lock().unwrap().clone();
                if active_tab_id == tab_id {
                    // 关闭当前显示的 Tab：回到“列表第一个站点”（排除被关闭站点）
                    if let Some(site_id) = first_site_id_excluding(&closed_site_id) {
                        CloseFallback::SwitchToFirstSite(site_id)
                    } else {
                        CloseFallback::ClearToEmpty
                    }
                } else {
                    CloseFallback::None
                }
            }
            LayoutMode::Split => {
                let left = layout.left_tab_id.clone();
                let right = layout.right_tab_id.clone();
                if left.as_deref() == Some(tab_id.as_str()) {
                    layout.left_tab_id = None;
                }
                if right.as_deref() == Some(tab_id.as_str()) {
                    layout.right_tab_id = None;
                }

                if layout.left_tab_id.is_none() || layout.right_tab_id.is_none() {
                    let remaining = layout.left_tab_id.clone().or(layout.right_tab_id.clone());
                    layout.mode = LayoutMode::Single;
                    layout.left_tab_id = None;
                    layout.right_tab_id = None;
                    if let Some(tab) = remaining {
                        CloseFallback::SwitchToTab(tab)
                    } else {
                        CloseFallback::None
                    }
                } else {
                    CloseFallback::None
                }
            }
        }
    };

    match fallback {
        CloseFallback::None => {}
        CloseFallback::ClearToEmpty => {
            *ACTIVE_TAB_ID.lock().unwrap() = String::new();
            *CURRENT_VIEW.lock().unwrap() = String::new();
        }
        CloseFallback::SwitchToFirstSite(site_id) => {
            *ACTIVE_TAB_ID.lock().unwrap() = String::new();
            *CURRENT_VIEW.lock().unwrap() = String::new();
            switch_view_inner(app.clone(), site_id).await?;
            return Ok(());
        }
        CloseFallback::SwitchToTab(tab) => {
            switch_tab_inner(app.clone(), tab).await?;
            return Ok(());
        }
    }

    resize_webviews_inner(&app, true)?;
    Ok(())
}

/// 切换视图（核心功能）
async fn switch_view_inner(app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    // 站点切换默认使用主 Tab（tab_id == site_id）并进入单视图模式
    let _ = get_site_by_id(&site_id)?;

    {
        let mut layout = LAYOUT_STATE.lock().unwrap();
        layout.mode = LayoutMode::Single;
        layout.left_tab_id = None;
        layout.right_tab_id = None;
    }

    *ACTIVE_TAB_ID.lock().unwrap() = site_id.clone();
    ensure_tab_webview(&app, &site_id, &site_id)?;
    resize_webviews_inner(&app, true)?;

    *CURRENT_VIEW.lock().unwrap() = site_id.clone();
    upsert_recent_site(&site_id);
    Ok(())
}

#[tauri::command]
async fn switch_view(webview: tauri::Webview, app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    switch_view_inner(app, site_id).await
}

/// 刷新当前视图
#[tauri::command]
fn refresh_view(webview: tauri::Webview, app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let views: Vec<String> = CREATED_VIEWS.lock().unwrap().keys().cloned().collect();
    for tab_id in views {
        if get_tab_site_id(&tab_id).ok().as_deref() != Some(site_id.as_str()) {
            continue;
        }
        let webview_label = format!("ai_{}", tab_id);
        if let Some(webview) = app.get_webview(&webview_label) {
            webview
                .eval("window.location.reload()")
                .map_err(|e| format!("刷新失败: {}", e))?;
        }
    }

    Ok(())
}

/// 清除站点缓存
#[tauri::command]
fn clear_view_cache(webview: tauri::Webview, app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    // 关闭该站点下所有 Tab Webview（含主 Tab）
    for tab_id in tab_ids_for_site(&site_id) {
        close_tab_webview(&app, &tab_id);
    }

    // 删除数据目录
    let data_dir = get_data_dir(&site_id);
    if data_dir.exists() {
        let _ = std::fs::remove_dir_all(&data_dir);
    }

    // 如果是当前视图，清除状态
    let current = CURRENT_VIEW.lock().unwrap().clone();
    if current == site_id {
        *CURRENT_VIEW.lock().unwrap() = String::new();
        *ACTIVE_TAB_ID.lock().unwrap() = String::new();
    }

    Ok(())
}

/// 打开开发者工具
#[tauri::command]
fn open_devtools(webview: tauri::Webview, app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let active_tab_id = ACTIVE_TAB_ID.lock().unwrap().clone();
    let preferred_tab = if !active_tab_id.is_empty()
        && get_tab_site_id(&active_tab_id).ok().as_deref() == Some(site_id.as_str())
    {
        Some(active_tab_id)
    } else {
        None
    };

    let tab_id = preferred_tab.unwrap_or_else(|| site_id.clone());
    let webview_label = format!("ai_{}", tab_id);
    if let Some(webview) = app.get_webview(&webview_label) {
        webview.open_devtools();
    }

    Ok(())
}

/// 设置侧边栏宽度（拖拽调整时调用）
#[tauri::command]
fn set_sidebar_width(webview: tauri::Webview, app: tauri::AppHandle, width: f64) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    // 更新配置中的侧边栏宽度
    {
        let mut config = APP_CONFIG.lock().unwrap();
        config.sidebar_width = width;
        const MIN_SIDEBAR_WIDTH: f64 = 64.0;
        if width > MIN_SIDEBAR_WIDTH {
            config.sidebar_expanded_width = width;
        }
        save_config(&config)?;
    }

    // 立即更新所有 Webview 位置
    resize_webviews_bounds_only(app)
}

/// 更新所有 Webview 尺寸（窗口调整大小时调用）
#[tauri::command]
fn resize_webviews(webview: tauri::Webview, app: tauri::AppHandle) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    resize_webviews_inner(&app, true)
}

fn resize_webviews_bounds_only(app: tauri::AppHandle) -> Result<(), String> {
    resize_webviews_inner(&app, false)
}

fn resize_webviews_inner(app: &tauri::AppHandle, apply_visibility: bool) -> Result<(), String> {
    let window = get_main_window(app)?;
    let (content_pos, content_size) = calculate_webview_bounds(&window);

    let layout = LAYOUT_STATE.lock().unwrap().clone();
    let active_tab_id = ACTIVE_TAB_ID.lock().unwrap().clone();
    let current_site_id = CURRENT_VIEW.lock().unwrap().clone();

    let mut visible: HashMap<String, (LogicalPosition<f64>, LogicalSize<f64>)> = HashMap::new();

    match layout.mode {
        LayoutMode::Single => {
            let tab_id = if !active_tab_id.is_empty() {
                active_tab_id
            } else {
                current_site_id
            };
            if !tab_id.is_empty() {
                visible.insert(tab_id, (content_pos, content_size));
            }
        }
        LayoutMode::Split => {
            if let (Some(left_tab), Some(right_tab)) = (layout.left_tab_id, layout.right_tab_id) {
                let ratio = layout.ratio.clamp(0.2, 0.8);
                let left_width = (content_size.width * ratio).max(100.0);
                let right_width = (content_size.width - left_width).max(100.0);

                visible.insert(
                    left_tab,
                    (
                        LogicalPosition::new(content_pos.x, content_pos.y),
                        LogicalSize::new(left_width, content_size.height),
                    ),
                );
                visible.insert(
                    right_tab,
                    (
                        LogicalPosition::new(content_pos.x + left_width, content_pos.y),
                        LogicalSize::new(right_width, content_size.height),
                    ),
                );
            } else if !current_site_id.is_empty() {
                visible.insert(current_site_id, (content_pos, content_size));
            }
        }
    }

    let views = CREATED_VIEWS.lock().unwrap().clone();
    for (tab_id, _) in views {
        let webview_label = format!("ai_{}", tab_id);
        if let Some(webview) = app.get_webview(&webview_label) {
            if let Some((pos, size)) = visible.get(&tab_id) {
                let _ = webview.set_position(*pos);
                let _ = webview.set_size(*size);
                if apply_visibility {
                    let _ = webview.show();
                }
            } else {
                if apply_visibility {
                    let _ = webview.hide();
                }
            }
        }
    }

    Ok(())
}

// ============================================================================
// 自定义站点和配置命令
// ============================================================================

/// 添加自定义站点
#[tauri::command]
fn add_site(webview: tauri::Webview, name: String, url: String, icon: String) -> Result<AiSite, String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let new_site = AiSite {
        id: format!("custom_{}", Uuid::new_v4().to_string().split('-').next().unwrap()),
        name,
        url,
        icon,
        builtin: false,
        summary_prompt_override: String::new(),
    };

    let mut config = APP_CONFIG.lock().unwrap();
    config.sites.push(new_site.clone());
    config.site_order.push(new_site.id.clone());
    save_config(&config)?;

    Ok(new_site)
}

/// 更新站点（支持内置与自定义站点的基本信息编辑）
#[tauri::command]
fn update_site(
    webview: tauri::Webview,
    app: tauri::AppHandle,
    site_id: String,
    name: String,
    url: String,
    icon: String,
    summary_prompt_override: Option<String>,
) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let (old_url, new_url, config_snapshot) = {
        let mut config = APP_CONFIG.lock().unwrap();
        let site = config
            .sites
            .iter_mut()
            .find(|s| s.id == site_id)
            .ok_or_else(|| "站点不存在".to_string())?;

        let old_url = site.url.clone();
        site.name = name;
        site.url = url;
        site.icon = icon;
        if let Some(override_template) = summary_prompt_override {
            site.summary_prompt_override = override_template;
        }
        let new_url = site.url.clone();

        (old_url, new_url, config.clone())
    };

    save_config(&config_snapshot)?;

    // 若 URL 变更，为确保生效，关闭已有 Webview，等待下次切换时按新 URL 重建
    if old_url != new_url {
        for tab_id in tab_ids_for_site(&site_id) {
            close_tab_webview(&app, &tab_id);
        }

        let current = CURRENT_VIEW.lock().unwrap().clone();
        let active_tab = ACTIVE_TAB_ID.lock().unwrap().clone();
        if current == site_id
            || (!active_tab.is_empty()
                && get_tab_site_id(&active_tab).ok().as_deref() == Some(site_id.as_str()))
        {
            *CURRENT_VIEW.lock().unwrap() = String::new();
            *ACTIVE_TAB_ID.lock().unwrap() = String::new();
            *LAYOUT_STATE.lock().unwrap() = LayoutState::default();
        }
    }

    Ok(())
}

/// 删除自定义站点
#[tauri::command]
fn remove_site(webview: tauri::Webview, app: tauri::AppHandle, site_id: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();

    // 检查是否为内置站点
    if let Some(site) = config.sites.iter().find(|s| s.id == site_id) {
        if site.builtin {
            return Err("无法删除内置站点".to_string());
        }
    } else {
        return Err("站点不存在".to_string());
    }

    // 删除站点
    config.sites.retain(|s| s.id != site_id);
    config.site_order.retain(|id| id != &site_id);
    config.pinned_site_ids.retain(|id| id != &site_id);
    config.recent_site_ids.retain(|id| id != &site_id);
    save_config(&config)?;

    // 关闭对应的 Webview
    drop(config);
    for tab_id in tab_ids_for_site(&site_id) {
        close_tab_webview(&app, &tab_id);
    }

    // 如果是当前视图，清除状态
    let current = CURRENT_VIEW.lock().unwrap().clone();
    if current == site_id {
        *CURRENT_VIEW.lock().unwrap() = String::new();
        *ACTIVE_TAB_ID.lock().unwrap() = String::new();
        *LAYOUT_STATE.lock().unwrap() = LayoutState::default();
    }

    Ok(())
}

/// 更新站点排序
#[tauri::command]
fn update_sites_order(webview: tauri::Webview, order: Vec<String>) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    let existing: HashSet<String> = config.sites.iter().map(|s| s.id.clone()).collect();

    let mut seen: HashSet<String> = HashSet::new();
    let mut next: Vec<String> = Vec::new();
    for id in order {
        if !existing.contains(&id) {
            continue;
        }
        if !seen.insert(id.clone()) {
            continue;
        }
        next.push(id);
    }
    for site in &config.sites {
        if seen.insert(site.id.clone()) {
            next.push(site.id.clone());
        }
    }

    config.site_order = next;
    save_config(&config)?;
    Ok(())
}

/// 置顶/取消置顶站点
#[tauri::command]
fn toggle_pin_site(webview: tauri::Webview, site_id: String, pinned: bool) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    if !config.sites.iter().any(|s| s.id == site_id) {
        return Err("站点不存在".to_string());
    }

    config.pinned_site_ids.retain(|id| id != &site_id);
    if pinned {
        config.pinned_site_ids.insert(0, site_id);
    }

    save_config(&config)?;
    Ok(())
}

/// 更新置顶站点顺序（仅组内排序）
#[tauri::command]
fn update_pinned_sites_order(webview: tauri::Webview, order: Vec<String>) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    let existing: std::collections::HashSet<String> =
        config.sites.iter().map(|s| s.id.clone()).collect();

    let mut seen = std::collections::HashSet::<String>::new();
    let mut next: Vec<String> = Vec::new();
    for id in order {
        if !existing.contains(&id) {
            continue;
        }
        if seen.contains(&id) {
            continue;
        }
        seen.insert(id.clone());
        next.push(id);
    }

    config.pinned_site_ids = next;
    save_config(&config)?;
    Ok(())
}

/// 清空最近使用列表
#[tauri::command]
fn clear_recent_sites(webview: tauri::Webview) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    config.recent_site_ids.clear();
    save_config(&config)?;
    Ok(())
}

/// 重置导航栏数据（排序/置顶/最近），保留站点本身
#[tauri::command]
fn reset_navigation(webview: tauri::Webview) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();

    // 同步清理 sites 重复项（避免侧边栏重复）
    let mut seen_sites: HashSet<String> = HashSet::new();
    config.sites.retain(|s| seen_sites.insert(s.id.clone()));

    config.pinned_site_ids.clear();
    config.recent_site_ids.clear();

    let existing: HashSet<String> = config.sites.iter().map(|s| s.id.clone()).collect();

    // 恢复默认顺序：先内置站点顺序，再追加自定义站点
    let builtin_order: Vec<String> = get_builtin_sites()
        .iter()
        .map(|s| s.id.clone())
        .filter(|id| existing.contains(id))
        .collect();

    let mut seen: HashSet<String> = HashSet::new();
    let mut next: Vec<String> = Vec::new();
    for id in builtin_order {
        if seen.insert(id.clone()) {
            next.push(id);
        }
    }
    for site in &config.sites {
        if seen.insert(site.id.clone()) {
            next.push(site.id.clone());
        }
    }
    config.site_order = next;

    save_config(&config)?;
    Ok(())
}

/// 设置主题
#[tauri::command]
fn set_theme(webview: tauri::Webview, theme: String) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let mut config = APP_CONFIG.lock().unwrap();
    config.theme = theme;
    save_config(&config)?;
    Ok(())
}

/// 显示/隐藏当前活跃的子 Webview（用于在主 UI 上方显示弹窗）
#[tauri::command]
fn set_active_view_visible(webview: tauri::Webview, app: tauri::AppHandle, visible: bool) -> Result<(), String> {
    if !is_main_invoker_webview(&webview) {
        return Err("Not allowed".to_string());
    }
    let layout = LAYOUT_STATE.lock().unwrap().clone();
    let active_tab_id = ACTIVE_TAB_ID.lock().unwrap().clone();
    let current_site_id = CURRENT_VIEW.lock().unwrap().clone();

    let mut targets: Vec<String> = Vec::new();
    match layout.mode {
        LayoutMode::Single => {
            if !active_tab_id.is_empty() {
                targets.push(active_tab_id);
            } else if !current_site_id.is_empty() {
                targets.push(current_site_id);
            }
        }
        LayoutMode::Split => {
            if let Some(left) = layout.left_tab_id {
                targets.push(left);
            }
            if let Some(right) = layout.right_tab_id {
                targets.push(right);
            }
        }
    }

    for tab_id in targets {
        let webview_label = format!("ai_{}", tab_id);
        if let Some(webview) = app.get_webview(&webview_label) {
            if visible {
                let _ = webview.show();
            } else {
                let _ = webview.hide();
            }
        }
    }

    Ok(())
}

// ============================================================================
// 应用入口
// ============================================================================

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            // 监听主窗口事件
            let app_handle = app.handle().clone();

            let window = if let Some(main_window) = app.get_webview_window("main") {
                Some(main_window.as_ref().window().clone())
            } else {
                app.get_window("main")
            };

            if let Some(window) = window {
                window.on_window_event(move |event| {
                    match event {
                        tauri::WindowEvent::Resized(_) => {
                            if WEBVIEW_CREATE_IN_PROGRESS.load(Ordering::SeqCst) > 0 {
                                return;
                            }
                            // 窗口大小改变，更新所有 Webview
                            let _ = resize_webviews_bounds_only(app_handle.clone());
                        }
                        tauri::WindowEvent::CloseRequested { .. } => {
                            // 关闭窗口时清理所有 Webview
                            let views = CREATED_VIEWS.lock().unwrap().clone();
                            for (site_id, _) in views {
                                let label = format!("ai_{}", site_id);
                                if let Some(wv) = app_handle.get_webview(&label) {
                                    let _ = wv.close();
                                }
                            }
                        }
                        _ => {}
                    }
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_config,
            set_ai_api_settings,
            set_language,
            set_summary_prompt_template,
            get_ai_sites,
            get_current_view,
            get_tabs_state,
            switch_view,
            create_tab,
            switch_tab,
            set_layout,
            close_tab,
            refresh_view,
            clear_view_cache,
            open_devtools,
            set_sidebar_width,
            resize_webviews,
            add_site,
            update_site,
            remove_site,
            update_sites_order,
            toggle_pin_site,
            update_pinned_sites_order,
            clear_recent_sites,
            reset_navigation,
            set_active_project,
            list_projects,
            get_project,
            create_project,
            update_project,
            delete_project,
            summarize_text,
            aihub_submit_page_text,
            set_active_tab_id,
            summarize_active_tab,
            set_theme,
            set_active_view_visible,
        ])
        .run(tauri::generate_context!())
        .expect("运行 Tauri 应用失败");
}

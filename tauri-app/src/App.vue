<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { listen, UnlistenFn } from "@tauri-apps/api/event";
import {
  createDiscreteApi,
  dateEnUS,
  dateEsAR,
  dateFrFR,
  dateJaJP,
  dateKoKR,
  dateZhCN,
  darkTheme,
  enUS,
  esAR,
  frFR,
  jaJP,
  koKR,
  NAlert,
  NButton,
  NCard,
  NConfigProvider,
  NDivider,
  NForm,
  NFormItem,
  NGlobalStyle,
  NInput,
  NInputNumber,
  NModal,
  NSelect,
  NSpace,
  NTabPane,
  NTabs,
  NSwitch,
  zhCN,
} from "naive-ui";

import AddSiteModal from "./components/modals/AddSiteModal.vue";
import SiteSettingsModal from "./components/modals/SiteSettingsModal.vue";
import SummaryModal from "./components/modals/SummaryModal.vue";
import Sidebar from "./components/Sidebar.vue";
import TopBar from "./components/TopBar.vue";
import type { AiSite, AppConfig } from "./types";
import { currentLanguage, setLanguage, supportedLanguages, t, type SupportedLanguage } from "./i18n";

// 状态
const sites = ref<AiSite[]>([]);
const currentView = ref<string>("");
const loading = ref<boolean>(false);
const theme = ref<string>("dark");
const naiveTheme = computed(() => (theme.value === "dark" ? darkTheme : null));

const { message, dialog } = createDiscreteApi(["message", "dialog"]);

// 侧边栏宽度
const MIN_SIDEBAR_WIDTH = 64;
const EXPANDED_WIDTH = 180;
const sidebarWidth = ref<number>(MIN_SIDEBAR_WIDTH);
const sidebarExpandedWidth = ref<number>(EXPANDED_WIDTH);
const isCollapsed = ref<boolean>(true);

// 站点管理
const pinnedSiteIds = ref<string[]>([]);
const recentSiteIds = ref<string[]>([]);
const siteSearch = ref<string>("");

// 设置弹窗
const showSettings = ref<boolean>(false);

// 添加站点对话框
const showAddDialog = ref<boolean>(false);

// 站点设置弹窗
const showSiteSettings = ref<boolean>(false);
const siteSettingsSite = ref<{ id: string; name: string; url: string; icon: string; summary_prompt_override?: string } | null>(null);

// 总结
const showSummaryModal = ref(false);
const summaryText = ref("");
const isSummarizing = ref(false);

const topBarRef = ref<InstanceType<typeof TopBar> | null>(null);

// 事件监听器
let unlistenLoading: UnlistenFn | null = null;
let unlistenLoaded: UnlistenFn | null = null;
let unlistenLoadFailed: UnlistenFn | null = null;

// AI API 设置（MVP：明文存 config.json）
const aiApiBaseUrl = ref("");
const aiApiModel = ref("");
const aiApiKey = ref("");

// i18n + 总结提示词（全局）
const language = computed(() => currentLanguage.value);
const globalSummaryPromptTemplate = ref("");

const naiveLocale = computed(() => {
  switch (language.value) {
    case "zh-CN":
      return zhCN;
    case "ja":
      return jaJP;
    case "ko":
      return koKR;
    case "fr":
      return frFR;
    case "es":
      return esAR;
    case "en":
    default:
      return enUS;
  }
});

const naiveDateLocale = computed(() => {
  switch (language.value) {
    case "zh-CN":
      return dateZhCN;
    case "ja":
      return dateJaJP;
    case "ko":
      return dateKoKR;
    case "fr":
      return dateFrFR;
    case "es":
      return dateEsAR;
    case "en":
    default:
      return dateEnUS;
  }
});

// 获取 AI 站点列表和配置
async function loadSites() {
  try {
    const config = await invoke<AppConfig>("get_config");
    sites.value = await invoke<AiSite[]>("get_ai_sites");
    currentView.value = await invoke<string>("get_current_view");
    theme.value = config.theme;
    sidebarWidth.value = config.sidebar_width;
    isCollapsed.value = config.sidebar_width <= MIN_SIDEBAR_WIDTH;
    sidebarExpandedWidth.value =
      typeof (config as any).sidebar_expanded_width === "number" && (config as any).sidebar_expanded_width > MIN_SIDEBAR_WIDTH
        ? (config as any).sidebar_expanded_width
        : EXPANDED_WIDTH;
    pinnedSiteIds.value = config.pinned_site_ids ?? [];
    recentSiteIds.value = config.recent_site_ids ?? [];
    aiApiBaseUrl.value = config.ai_api_base_url ?? "";
    aiApiModel.value = config.ai_api_model ?? "";
    aiApiKey.value = config.ai_api_key ?? "";
    globalSummaryPromptTemplate.value = config.summary_prompt_template ?? "";

    const nextLang = (config.language ?? "zh-CN") as SupportedLanguage;
    if (supportedLanguages.some((l) => l.value === nextLang)) {
      setLanguage(nextLang);
    } else {
      setLanguage("zh-CN");
    }

    // 应用主题
    document.documentElement.dataset.theme = config.theme;
  } catch (error) {
    console.error("加载配置失败:", error);
    showError(t("common.loadConfigFailed"));
  }
}

// 切换视图
async function switchView(siteId: string) {
  if (loading.value) return;

  try {
    loading.value = true;
    console.log("切换到:", siteId);
    await invoke("switch_view", { siteId });
    currentView.value = siteId;
    recentSiteIds.value = [siteId, ...recentSiteIds.value.filter((id) => id !== siteId)].slice(0, 10);
    await topBarRef.value?.refresh?.();
  } catch (error) {
    console.error("切换视图失败:", error);
    showError(`切换失败: ${error}`);
  } finally {
    loading.value = false;
  }
}

// 刷新当前视图
async function refreshView(siteId: string) {
  try {
    await invoke("refresh_view", { siteId });
  } catch (error) {
    console.error("刷新失败:", error);
    showError(t("common.refreshFailed"));
  }
}

// 清除缓存
async function clearCache(siteId: string) {
  try {
    await invoke("clear_view_cache", { siteId });
    if (siteId === currentView.value) {
      currentView.value = "";
    }
  } catch (error) {
    console.error("清除缓存失败:", error);
    showError(t("common.clearCacheFailed"));
  }
}

// 打开开发者工具
async function openDevtools(siteId: string) {
  try {
    await invoke("open_devtools", { siteId });
  } catch (error) {
    console.error("打开开发者工具失败:", error);
  }
}

// 显示错误提示
function showError(msg: string) {
  message.error(msg);
}

// ========== 主题切换 ==========
async function setTheme(newTheme: "dark" | "light") {
  theme.value = newTheme;
  document.documentElement.dataset.theme = newTheme;

  try {
    await invoke("set_theme", { theme: newTheme });
  } catch (error) {
    console.error("保存主题失败:", error);
  }
}

async function toggleTheme() {
  await setTheme(theme.value === "dark" ? "light" : "dark");
}

const isDarkTheme = computed({
  get: () => theme.value === "dark",
  set: (value: boolean) => {
    void setTheme(value ? "dark" : "light");
  },
});

// ========== 添加站点 ==========
function openAddDialog() {
  showAddDialog.value = true;
}

function closeAddDialog() {
  showAddDialog.value = false;
}

async function addSite(payload: { name: string; url: string; icon: string }) {
  if (!payload.name.trim() || !payload.url.trim()) {
    showError(t("common.fillNameUrl"));
    return;
  }

  // 确保 URL 以 http:// 或 https:// 开头
  const url = normalizeUrl(payload.url);

  try {
    await invoke("add_site", {
      name: payload.name.trim(),
      url: url,
      icon: payload.icon,
    });
    await loadSites();
    closeAddDialog();
    await topBarRef.value?.refresh?.();
  } catch (error) {
    console.error("添加站点失败:", error);
    showError(`添加失败: ${error}`);
  }
}

// ========== 删除站点 ==========
async function removeSite(siteId: string) {
  try {
    await invoke("remove_site", { siteId });
    await loadSites();
    await topBarRef.value?.refresh?.();
  } catch (error) {
    console.error("删除站点失败:", error);
    showError(`删除失败: ${error}`);
  }
}

function openSiteSettings(siteId: string) {
  const site = sites.value.find((s) => s.id === siteId);
  if (!site) {
    showError(t("common.siteNotFound"));
    return;
  }

  siteSettingsSite.value = {
    id: site.id,
    name: site.name,
    url: site.url,
    icon: site.icon || "custom",
    summary_prompt_override: site.summary_prompt_override ?? "",
  };
  showSiteSettings.value = true;
}

function closeSiteSettings() {
  showSiteSettings.value = false;
  siteSettingsSite.value = null;
}

function normalizeUrl(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return trimmed;
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed;
  return "https://" + trimmed;
}

async function saveSiteSettings(payload: { id: string; name: string; url: string; icon: string; summary_prompt_override?: string }) {
  if (!payload.name.trim() || !payload.url.trim()) {
    showError(t("common.fillNameUrl"));
    return;
  }

  const url = normalizeUrl(payload.url);

  try {
    await invoke("update_site", {
      siteId: payload.id,
      name: payload.name.trim(),
      url,
      icon: payload.icon,
      summaryPromptOverride: payload.summary_prompt_override ?? "",
    });
    await loadSites();
    closeSiteSettings();
    await topBarRef.value?.refresh?.();
  } catch (error) {
    console.error("保存站点设置失败:", error);
    showError(`保存失败: ${error}`);
  }
}

async function saveUiLanguage(value: string | null) {
  if (!value) return;
  const lang = value as SupportedLanguage;
  if (!supportedLanguages.some((l) => l.value === lang)) return;
  setLanguage(lang);
  try {
    await invoke("set_language", { language: lang });
  } catch (e) {
    console.error("保存语言失败:", e);
  }
}

async function saveGlobalSummaryPromptTemplate() {
  try {
    await invoke("set_summary_prompt_template", { template: globalSummaryPromptTemplate.value });
    try {
      const cfg = await invoke<AppConfig>("get_config");
      globalSummaryPromptTemplate.value = cfg.summary_prompt_template ?? globalSummaryPromptTemplate.value;
    } catch {
      // ignore
    }
    message.success(t("settings.save"));
  } catch (e) {
    console.error("保存总结提示词失败:", e);
    showError(`保存失败: ${e}`);
  }
}

async function resetGlobalSummaryPromptTemplate() {
  globalSummaryPromptTemplate.value = "";
  await saveGlobalSummaryPromptTemplate();
}

// ========== 一键展开/收缩侧边栏 ==========
async function setSidebarWidth(width: number) {
  const safeWidth = Math.max(MIN_SIDEBAR_WIDTH, Math.round(width));
  sidebarWidth.value = safeWidth;
  isCollapsed.value = safeWidth <= MIN_SIDEBAR_WIDTH;
  if (safeWidth > MIN_SIDEBAR_WIDTH) {
    sidebarExpandedWidth.value = safeWidth;
  }

  try {
    await invoke("set_sidebar_width", { width: safeWidth });
  } catch (err) {
    console.error("设置侧边栏宽度失败:", err);
  }
}

async function toggleSidebar() {
  const nextWidth = isCollapsed.value ? sidebarExpandedWidth.value : MIN_SIDEBAR_WIDTH;
  await setSidebarWidth(nextWidth);
}

const isSidebarExpanded = computed({
  get: () => !isCollapsed.value,
  set: (value: boolean) => {
    void setSidebarWidth(value ? sidebarExpandedWidth.value : MIN_SIDEBAR_WIDTH);
  },
});

function openSettings() {
  showSettings.value = true;
}

async function summarizeCurrentTab() {
  if (isSummarizing.value) return;
  isSummarizing.value = true;
  try {
    const result = await invoke<string>("summarize_active_tab");
    summaryText.value = result;
    showSummaryModal.value = true;
  } catch (e) {
    console.error("总结失败:", e);
    showError(`总结失败: ${e}`);
  } finally {
    isSummarizing.value = false;
  }
}

function onSettingsSidebarWidthUpdate(value: number | null) {
  if (typeof value === "number") {
    void setSidebarWidth(value);
  }
}

async function saveAiApiSettings() {
  try {
    await invoke("set_ai_api_settings", {
      baseUrl: aiApiBaseUrl.value,
      model: aiApiModel.value,
      apiKey: aiApiKey.value,
      clearKey: false,
    });
    aiApiKey.value = "";
    message.success(t("settings.aiApiSaved"));
  } catch (e) {
    console.error("保存 AI API 设置失败:", e);
    showError(`保存失败: ${e}`);
  }
}

async function clearAiApiKey() {
  const ok = window.confirm(t("settings.clearApiKeyConfirm"));
  if (!ok) return;
  try {
    await invoke("set_ai_api_settings", {
      baseUrl: aiApiBaseUrl.value,
      model: aiApiModel.value,
      apiKey: "",
      clearKey: true,
    });
    aiApiKey.value = "";
    message.success(t("settings.apiKeyCleared"));
  } catch (e) {
    console.error("清空 API Key 失败:", e);
    showError(`清空失败: ${e}`);
  }
}

async function resetNavigation() {
  dialog.warning({
    title: t("settings.resetNavTitle"),
    content: t("settings.resetNavContent"),
    positiveText: t("settings.resetNavConfirm"),
    negativeText: t("settings.cancel"),
    onPositiveClick: async () => {
      try {
        await invoke("reset_navigation");
        await loadSites();
        message.success(t("settings.resetNavToast"));
      } catch (e) {
        console.error("重置导航栏失败:", e);
        showError(t("settings.resetNavError"));
      }
    },
  });
}

const isOverlayOpen = computed(() => showSettings.value || showAddDialog.value || showSiteSettings.value || showSummaryModal.value);

const pinnedSet = computed(() => new Set(pinnedSiteIds.value));
const query = computed(() => siteSearch.value.trim().toLowerCase());

function siteMatchesQuery(site: AiSite): boolean {
  if (!query.value) return true;
  const q = query.value;
  return site.name.toLowerCase().includes(q) || site.url.toLowerCase().includes(q);
}

const siteById = computed(() => new Map(sites.value.map((s) => [s.id, s])));
const pinnedSites = computed(() =>
  pinnedSiteIds.value
    .map((id) => siteById.value.get(id))
    .filter((s): s is AiSite => Boolean(s))
    .filter(siteMatchesQuery),
);
const allRecentSites = computed(() =>
  recentSiteIds.value
    .map((id) => siteById.value.get(id))
    .filter((s): s is AiSite => Boolean(s))
    .filter((s) => !pinnedSet.value.has(s.id))
    .filter(siteMatchesQuery),
);
const recentSitesShown = computed(() => allRecentSites.value.slice(0, 5));
const recentShownSet = computed(() => new Set(recentSitesShown.value.map((s) => s.id)));

const unpinnedSites = computed(() =>
  sites.value
    .filter((s) => !pinnedSet.value.has(s.id))
    // 为避免“最近”区块与主列表重复，主列表里隐藏最近项（展开/收缩保持一致顺序）
    .filter((s) => !(showRecentSection.value && recentShownSet.value.has(s.id)))
    .filter(siteMatchesQuery),
);

const showRecentSection = computed(() => !query.value && allRecentSites.value.length > 0);

watch(isOverlayOpen, async (open) => {
  try {
    await invoke("set_active_view_visible", { visible: !open });
  } catch (e) {
    console.error("切换子 Webview 显示失败:", e);
  }
});

async function togglePinSite(siteId: string, pinned: boolean) {
  try {
    await invoke("toggle_pin_site", { siteId, pinned });
    pinnedSiteIds.value = pinned
      ? [siteId, ...pinnedSiteIds.value.filter((id) => id !== siteId)]
      : pinnedSiteIds.value.filter((id) => id !== siteId);
  } catch (error) {
    console.error("更新置顶失败:", error);
    showError("更新置顶失败");
  }
}

async function reorderPinnedSites(order: string[]) {
  try {
    await invoke("update_pinned_sites_order", { order });
    pinnedSiteIds.value = order;
  } catch (error) {
    console.error("更新置顶排序失败:", error);
    showError("更新置顶排序失败");
  }
}

async function reorderSites(order: string[]) {
  try {
    await invoke("update_sites_order", { order });
    await loadSites();
  } catch (error) {
    console.error("更新排序失败:", error);
    showError("更新排序失败");
  }
}

// 初始化
onMounted(async () => {
  await loadSites();

  // 监听 Webview 加载事件
  unlistenLoading = await listen<string>("webview-loading", () => {
    loading.value = true;
  });

  unlistenLoaded = await listen<string>("webview-loaded", () => {
    loading.value = false;
  });

  unlistenLoadFailed = await listen<{
    tab_id: string;
    site_id: string;
    url: string;
    message: string;
  }>("webview-load-failed", async (event) => {
    loading.value = false;
    const payload = event.payload;
    if (payload?.message) {
      showError(payload.message);
    } else {
      showError("页面加载失败");
    }

    try {
      currentView.value = await invoke<string>("get_current_view");
      await topBarRef.value?.refresh?.();
    } catch (error) {
      console.error("刷新视图状态失败:", error);
    }
  });
});

// 清理
onUnmounted(() => {
  if (unlistenLoading) unlistenLoading();
  if (unlistenLoaded) unlistenLoaded();
  if (unlistenLoadFailed) unlistenLoadFailed();
});
</script>

<template>
  <n-config-provider :theme="naiveTheme" :locale="naiveLocale" :date-locale="naiveDateLocale">
    <n-global-style />
    <div class="app-container">
      <sidebar
        v-model:search="siteSearch"
        :pinned-sites="pinnedSites"
        :unpinned-sites="unpinnedSites"
        :recent-sites="recentSitesShown"
        :show-recent="showRecentSection"
        :current-view="currentView"
        :sidebar-width="sidebarWidth"
        :min-sidebar-width="MIN_SIDEBAR_WIDTH"
        :is-collapsed="isCollapsed"
        :theme="theme as any"
        :pinned-site-ids="pinnedSiteIds"
        @switch-site="switchView"
        @open-add-site="openAddDialog"
        @open-settings="openSettings"
        @toggle-theme="toggleTheme"
        @toggle-sidebar="toggleSidebar"
        @open-site-settings="openSiteSettings"
        @toggle-pin="togglePinSite"
        @refresh="refreshView"
        @clear-cache="clearCache"
        @devtools="openDevtools"
        @remove-site="removeSite"
        @reorder-pinned="reorderPinnedSites"
        @reorder-sites="reorderSites"
      />

      <div class="main-area">
        <top-bar
          ref="topBarRef"
          :sites="sites"
          :current-site-id="currentView"
          :summarizing="isSummarizing"
          @summarize="summarizeCurrentTab"
        />

    <!-- 加载指示器 -->
    <div v-if="loading" class="loading-bar" :style="{ left: sidebarWidth + 'px' }"></div>

    <!-- 主内容区域（欢迎页面） -->
    <main v-if="!currentView" class="content">
      <div class="welcome-screen">
        <div class="welcome-icon">🚀</div>
        <h2>{{ t("app.welcomeTitle") }}</h2>
        <p>{{ t("app.welcomeSubtitle") }}</p>
      </div>
    </main>
      </div>

    <add-site-modal v-model:show="showAddDialog" @submit="addSite" @error="showError" />
    <site-settings-modal
      v-model:show="showSiteSettings"
      :site="siteSettingsSite"
      @submit="saveSiteSettings"
      @error="showError"
    />
    <summary-modal v-model:show="showSummaryModal" v-model:summary="summaryText" />
    </div>

    <n-modal v-model:show="showSettings" :mask-closable="true" :close-on-esc="true">
      <n-card
        :title="t('settings.title')"
        closable
        :bordered="false"
        size="large"
        :segmented="{ footer: 'soft' }"
        :content-style="{ maxHeight: 'calc(100vh - 220px)', overflow: 'auto' }"
        style="width: 560px; max-width: calc(100vw - 32px)"
        @close="showSettings = false"
      >
        <n-tabs type="line" animated default-value="appearance">
          <n-tab-pane name="appearance" :tab="t('settings.tabs.appearance')">
            <n-form label-placement="left" label-width="120" size="medium">
              <n-form-item :label="t('settings.darkTheme')">
                <n-switch v-model:value="isDarkTheme" />
              </n-form-item>
            </n-form>
          </n-tab-pane>

          <n-tab-pane name="layout" :tab="t('settings.tabs.layout')">
            <n-form label-placement="left" label-width="120" size="medium">
              <n-form-item :label="t('settings.sidebarExpand')">
                <n-switch v-model:value="isSidebarExpanded" />
              </n-form-item>
              <n-form-item :label="t('settings.sidebarWidth')">
                <n-input-number
                  :disabled="!isSidebarExpanded"
                  :min="MIN_SIDEBAR_WIDTH"
                  :max="260"
                  :step="4"
                  :value="sidebarWidth"
                  style="width: 220px"
                  @update:value="onSettingsSidebarWidthUpdate"
                />
              </n-form-item>
            </n-form>
          </n-tab-pane>

          <n-tab-pane name="language" :tab="t('settings.tabs.language')">
            <n-space vertical size="medium">
              <n-form label-placement="left" label-width="120" size="medium">
                <n-form-item :label="t('settings.language')">
                  <n-select
                    style="width: 220px"
                    :value="language"
                    :options="supportedLanguages"
                    @update:value="saveUiLanguage"
                  />
                </n-form-item>
              </n-form>
              <n-alert type="info" :show-icon="false">
                {{ t("settings.languageHint") }}
              </n-alert>
            </n-space>
          </n-tab-pane>

          <n-tab-pane name="ai" :tab="t('settings.tabs.ai')">
            <n-space vertical size="large">
              <n-form label-placement="left" label-width="120" size="medium">
                <n-form-item label="Base URL">
                  <n-input v-model:value="aiApiBaseUrl" placeholder="https://api.openai.com/v1" />
                </n-form-item>
                <n-form-item label="Model">
                  <n-input v-model:value="aiApiModel" placeholder="例如：gpt-4o-mini / deepseek-chat" />
                </n-form-item>
                <n-form-item label="API Key">
                  <n-input v-model:value="aiApiKey" type="password" show-password-on="click" placeholder="已保存（不回显）；留空表示不修改" />
                </n-form-item>
                <n-form-item>
                  <div style="display: flex; gap: 10px; flex-wrap: wrap">
                    <n-button type="primary" @click="saveAiApiSettings">{{ t("settings.saveApiSettings") }}</n-button>
                    <n-button tertiary type="warning" @click="clearAiApiKey">{{ t("settings.clearKey") }}</n-button>
                  </div>
                </n-form-item>
              </n-form>

              <n-divider style="margin: 0" />

              <n-space vertical size="small">
                <n-form label-placement="top" size="medium">
                  <n-form-item :label="t('settings.summaryPromptTemplate')">
                    <n-input
                      v-model:value="globalSummaryPromptTemplate"
                      type="textarea"
                      :autosize="{ minRows: 8, maxRows: 14 }"
                      :placeholder="t('settings.summaryPromptHint', { language: '{language}', text: '{text}' })"
                    />
                  </n-form-item>
                </n-form>
                <n-alert type="info" :show-icon="false">
                  {{ t("settings.summaryPromptHint", { language: "{language}", text: "{text}" }) }}
                </n-alert>
                <div style="display: flex; gap: 10px; flex-wrap: wrap; justify-content: flex-end">
                  <n-button tertiary @click="resetGlobalSummaryPromptTemplate">{{ t("settings.resetToDefault") }}</n-button>
                  <n-button type="primary" @click="saveGlobalSummaryPromptTemplate">{{ t("settings.savePromptTemplate") }}</n-button>
                </div>
              </n-space>
            </n-space>
          </n-tab-pane>

          <n-tab-pane name="advanced" :tab="t('settings.tabs.advanced')">
            <n-alert type="warning" :bordered="false">
              {{ t("settings.resetNavContent") }}
            </n-alert>
            <div style="margin-top: 12px">
              <n-button tertiary type="error" @click="resetNavigation">{{ t("settings.resetNavButton") }}</n-button>
            </div>
          </n-tab-pane>
        </n-tabs>

        <template #footer>
          <div style="display: flex; justify-content: flex-end; gap: 10px">
            <n-button @click="showSettings = false">{{ t("settings.cancel") }}</n-button>
            <n-button type="primary" @click="showSettings = false">{{ t("settings.done") }}</n-button>
          </div>
        </template>
      </n-card>
    </n-modal>
  </n-config-provider>
</template>

<style>
/* 深色主题（默认） */
:root, [data-theme="dark"] {
  --bg-dark: #1e1e2e;
  --bg-darker: #181825;
  --bg-surface: #313244;
  --text-primary: #cdd6f4;
  --text-secondary: #a6adc8;
  --accent-color: #89b4fa;
  --border-color: #45475a;
  --hover-bg: #313244;
  --active-bg: rgba(137, 180, 250, 0.15);
  --error: #f38ba8;
  --danger: #f38ba8;
}

/* 浅色主题 */
[data-theme="light"] {
  --bg-dark: #eff1f5;
  --bg-darker: #e6e9ef;
  --bg-surface: #dce0e8;
  --text-primary: #4c4f69;
  --text-secondary: #6c6f85;
  --accent-color: #1e66f5;
  --border-color: #ccd0da;
  --hover-bg: #dce0e8;
  --active-bg: rgba(30, 102, 245, 0.15);
  --error: #d20f39;
  --danger: #d20f39;
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: var(--bg-dark);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}
</style>

<style scoped>
.app-container {
  display: flex;
  width: 100%;
  height: 100vh;
  background: var(--bg-dark);
  color: var(--text-primary);
  position: relative;
}

.main-area {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

/* 主内容区 */
.content {
  flex: 1;
  position: relative;
  background: var(--bg-dark);
  display: flex;
  align-items: center;
  justify-content: center;
}

/* 欢迎屏幕 */
.welcome-screen {
  text-align: center;
  color: var(--text-secondary);
}

.welcome-icon {
  font-size: 64px;
  margin-bottom: 16px;
}

.welcome-screen h2 {
  font-size: 24px;
  margin-bottom: 8px;
  color: var(--text-primary);
}

.welcome-screen p {
  font-size: 14px;
}

/* 加载条 */
.loading-bar {
  position: fixed;
  top: 0;
  right: 0;
  height: 3px;
  background: linear-gradient(90deg, var(--accent-color), #cba6f7, var(--accent-color));
  background-size: 200% 100%;
  animation: loading 1.5s ease infinite;
  z-index: 1000;
}

@keyframes loading {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

</style>

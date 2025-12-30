<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { createDiscreteApi, NButton, NIcon, NSelect, NSlider, NSwitch } from "naive-ui";
import { AddOutline, CloseOutline, DocumentTextOutline, GridOutline } from "@vicons/ionicons5";

import type { AiSite } from "../types";
import { t } from "../i18n";

type TabsStateResponse = {
  active_tab_id: string;
  mode: "single" | "split";
  ratio: number;
  left_tab_id: string | null;
  right_tab_id: string | null;
  tabs: Array<{ tab_id: string; site_id: string }>;
};

const props = defineProps<{
  sites: AiSite[];
  currentSiteId: string;
  summarizing?: boolean;
}>();

const emit = defineEmits<{
  (e: "summarize"): void;
}>();

const tabsState = ref<TabsStateResponse | null>(null);
const busy = ref(false);

const { message } = createDiscreteApi(["message"]);

const siteNameById = computed(() => new Map(props.sites.map((s) => [s.id, s.name])));
const tabsBySite = computed(() => {
  const counts = new Map<string, number>();
  for (const t of tabsState.value?.tabs ?? []) {
    counts.set(t.site_id, (counts.get(t.site_id) ?? 0) + 1);
  }
  return counts;
});

function tabTitle(tab: { tab_id: string; site_id: string }): string {
  const base = siteNameById.value.get(tab.site_id) ?? tab.site_id;
  const count = tabsBySite.value.get(tab.site_id) ?? 0;
  if (count <= 1) return base;
  if (tab.tab_id === tab.site_id) return `${base} (1)`;
  return `${base} (${t("top.multiSession")})`;
}

const tabOptions = computed(() =>
  (tabsState.value?.tabs ?? []).map((t) => ({ label: tabTitle(t), value: t.tab_id })),
);

const splitEnabled = computed(() => tabsState.value?.mode === "split");
const canEnableSplit = computed(() => (tabsState.value?.tabs?.length ?? 0) >= 2);
const visibleTabIds = computed(() => {
  if (!tabsState.value) return new Set<string>();
  if (tabsState.value.mode === "split") {
    return new Set([tabsState.value.left_tab_id ?? "", tabsState.value.right_tab_id ?? ""].filter(Boolean));
  }
  return new Set([tabsState.value.active_tab_id].filter(Boolean));
});

const activeSelectCount = ref(0);

async function refresh() {
  tabsState.value = await invoke<TabsStateResponse>("get_tabs_state");
}

defineExpose({ refresh });

async function switchTab(tabId: string) {
  if (!tabId) return;
  busy.value = true;
  try {
    await invoke("switch_tab", { tabId });
    await refresh();
  } finally {
    busy.value = false;
  }
}

async function createTabForCurrentSite() {
  if (!props.currentSiteId) return;
  busy.value = true;
  try {
    const tabId = await invoke<string>("create_tab", { siteId: props.currentSiteId });
    await invoke("switch_tab", { tabId });
    await invoke("set_active_tab_id", { tabId });
    await refresh();
  } finally {
    busy.value = false;
  }
}

async function closeTab(tabId: string) {
  if (!tabId) return;
  busy.value = true;
  try {
    await invoke("close_tab", { tabId });
    await refresh();
  } finally {
    busy.value = false;
  }
}

function onSelectShow(show: boolean) {
  activeSelectCount.value = Math.max(0, activeSelectCount.value + (show ? 1 : -1));
}

watch(
  () => activeSelectCount.value,
  async (count) => {
    try {
      await invoke("set_active_view_visible", { visible: count <= 0 });
    } catch {
      // ignore
    }
  },
);

async function setSplit(enabled: boolean) {
  busy.value = true;
  try {
    if (!enabled) {
      await invoke("set_layout", { mode: "single" });
      await refresh();
      return;
    }

    const state = tabsState.value;
    if (!state) return;

    if (!canEnableSplit.value) {
      message.warning(t("top.splitNeedTwoTabs"));
      await refresh();
      return;
    }

    const active = state.active_tab_id || props.currentSiteId || "";
    if (!active) {
      message.warning(t("top.splitNeedTwoTabs"));
      await refresh();
      return;
    }

    const leftTabId = state.left_tab_id || active;
    await invoke("set_layout", { mode: "split", ratio: state.ratio || 0.5, leftTabId });
    await invoke("set_active_tab_id", { tabId: leftTabId });
    await refresh();
  } finally {
    busy.value = false;
  }
}

async function updateSplitRatio(ratio: number) {
  if (!tabsState.value || tabsState.value.mode !== "split") return;
  const { left_tab_id, right_tab_id } = tabsState.value;
  if (!left_tab_id || !right_tab_id) return;
  await invoke("set_layout", { mode: "split", ratio, leftTabId: left_tab_id, rightTabId: right_tab_id });
  await refresh();
}

async function updateSplitTabs(leftTabId: string | null, rightTabId: string | null) {
  if (!tabsState.value) return;
  if (!leftTabId && !rightTabId) return;
  await invoke("set_layout", {
    mode: "split",
    ratio: tabsState.value.ratio,
    leftTabId: leftTabId ?? null,
    rightTabId: rightTabId ?? null,
  });
  await refresh();
}

async function updateLeftTab(leftTabId: string | null) {
  if (!tabsState.value || !leftTabId) return;
  await updateSplitTabs(leftTabId, tabsState.value.right_tab_id ?? null);
  await invoke("set_active_tab_id", { tabId: leftTabId });
}

async function updateRightTab(rightTabId: string | null) {
  if (!tabsState.value || !rightTabId) return;
  const leftFallback =
    tabsState.value.left_tab_id || tabsState.value.active_tab_id || props.currentSiteId || null;
  await updateSplitTabs(leftFallback, rightTabId);
  await invoke("set_active_tab_id", { tabId: rightTabId });
}

onMounted(() => {
  void refresh();
});
</script>

<template>
  <header class="topbar">
    <div class="left">
      <n-button size="small" :disabled="busy || !currentSiteId" @click="createTabForCurrentSite">
        <template #icon>
          <n-icon>
            <add-outline />
          </n-icon>
        </template>
        {{ t("top.newTab") }}
      </n-button>

      <n-button
        size="small"
        :disabled="busy || summarizing"
        :loading="summarizing"
        @click="emit('summarize')"
      >
        <template #icon>
          <n-icon>
            <document-text-outline />
          </n-icon>
        </template>
        {{ summarizing ? t("top.summarizing") : t("top.summarize") }}
      </n-button>

      <div class="split">
        <n-switch size="small" :disabled="busy || !canEnableSplit" :value="splitEnabled" @update:value="setSplit" />
        <div class="split-label">
          <n-icon size="16"><grid-outline /></n-icon>
          {{ t("top.split") }}
        </div>
      </div>
    </div>

    <div class="tabs">
      <div v-for="tab in tabsState?.tabs ?? []" :key="tab.tab_id" class="tab" :class="{ active: visibleTabIds.has(tab.tab_id) }">
        <button class="tab-btn" :disabled="busy" @click="switchTab(tab.tab_id)" :title="tabTitle(tab)">
          {{ tabTitle(tab) }}
        </button>
        <button
          class="tab-close"
          :disabled="busy"
          :title="t('top.closeTab')"
          @click.stop="closeTab(tab.tab_id)"
        >
          <n-icon size="14"><close-outline /></n-icon>
        </button>
      </div>
    </div>

    <div class="divider" aria-hidden="true"></div>

    <div v-if="tabsState?.mode === 'split'" class="right">
      <n-select
        size="small"
        style="width: 170px"
        :disabled="busy"
        :value="tabsState.left_tab_id"
        :options="tabOptions"
        @update:show="onSelectShow"
        @update:value="(v) => updateLeftTab(v as string)"
      />
      <n-select
        size="small"
        style="width: 170px"
        :disabled="busy"
        :value="tabsState.right_tab_id"
        :options="tabOptions"
        @update:show="onSelectShow"
        @update:value="(v) => updateRightTab(v as string)"
      />
      <n-slider
        style="width: 140px"
        :disabled="busy || !tabsState?.left_tab_id || !tabsState?.right_tab_id"
        :min="0.2"
        :max="0.8"
        :step="0.05"
        :value="tabsState.ratio"
        @update:value="updateSplitRatio"
      />
    </div>
  </header>
</template>

<style scoped>
.topbar {
  height: 48px;
  min-height: 48px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  background: var(--bg-darker);
  border-bottom: 1px solid var(--border-color);
}

.left {
  display: flex;
  align-items: center;
  gap: 12px;
}

.split {
  display: flex;
  align-items: center;
  gap: 8px;
}

.split-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--text-secondary);
}

.tabs {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 6px;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: thin;
  padding-bottom: 2px;
}

.tabs::-webkit-scrollbar {
  height: 8px;
}
.tabs::-webkit-scrollbar-thumb {
  background: var(--border-color);
  border-radius: 999px;
}

.divider {
  width: 1px;
  height: 26px;
  background: var(--border-color);
  opacity: 0.8;
}

.tab {
  display: flex;
  align-items: center;
  gap: 6px;
  background: var(--bg-surface);
  border: 1px solid var(--border-color);
  border-radius: 10px;
  overflow: hidden;
  max-width: 220px;
}

.tab.active {
  border-color: var(--accent-color);
}

.tab:hover {
  border-color: color-mix(in srgb, var(--border-color) 60%, var(--accent-color));
}

.tab-btn {
  cursor: pointer;
  border: 0;
  background: transparent;
  color: var(--text-primary);
  padding: 6px 8px;
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 170px;
}

.tab-btn:disabled {
  cursor: not-allowed;
  opacity: 0.7;
}

.tab-close {
  cursor: pointer;
  border: 0;
  background: transparent;
  color: var(--text-secondary);
  width: 26px;
  height: 26px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  margin-right: 4px;
}

.tab-close:hover:not(:disabled) {
  color: var(--text-primary);
  background: var(--active-bg);
}

.tab-close:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.right {
  display: flex;
  align-items: center;
  gap: 8px;
}
</style>

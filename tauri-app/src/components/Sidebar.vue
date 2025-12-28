<script setup lang="ts">
import { h, ref, computed } from "vue";
import { NDropdown, NIcon, NInput } from "naive-ui";
import { AddOutline, BrushOutline, ChevronBackOutline, ChevronForwardOutline, ConstructOutline, MoonOutline, RefreshOutline, SettingsOutline, Star, StarOutline, SunnyOutline, TrashOutline } from "@vicons/ionicons5";

import type { AiSite } from "../types";
import { getIconUrl, getXiconComponentOrNull } from "../composables/useIcons";
import appLogo from "../assets/logo.png";
import { t } from "../i18n";

const props = defineProps<{
  pinnedSites: AiSite[];
  unpinnedSites: AiSite[];
  recentSites: AiSite[];
  showRecent: boolean;
  currentView: string;
  sidebarWidth: number;
  minSidebarWidth: number;
  isCollapsed: boolean;
  theme: "dark" | "light";
  pinnedSiteIds: string[];
}>();

const emit = defineEmits<{
  (e: "update:search", value: string): void;
  (e: "switch-site", siteId: string): void;
  (e: "open-add-site"): void;
  (e: "open-settings"): void;
  (e: "toggle-theme"): void;
  (e: "toggle-sidebar"): void;
  (e: "open-site-settings", siteId: string): void;
  (e: "toggle-pin", siteId: string, pinned: boolean): void;
  (e: "refresh", siteId: string): void;
  (e: "clear-cache", siteId: string): void;
  (e: "devtools", siteId: string): void;
  (e: "remove-site", siteId: string): void;
  (e: "reorder-pinned", order: string[]): void;
  (e: "reorder-sites", order: string[]): void;
}>();

const search = defineModel<string>("search", { required: true });

const sidebarEl = ref<HTMLElement | null>(null);

const contextMenu = ref<{ show: boolean; x: number; y: number; siteId: string; isBuiltin: boolean }>({
  show: false,
  x: 0,
  y: 0,
  siteId: "",
  isBuiltin: true,
});

const pinnedSet = computed(() => new Set(props.pinnedSiteIds));

const contextMenuOptions = computed(() => {
  const isPinned = contextMenu.value.siteId ? pinnedSet.value.has(contextMenu.value.siteId) : false;
  const isBuiltin = contextMenu.value.isBuiltin;
  const options: any[] = [
    {
      label: t("sidebar.menu.siteSettings"),
      key: "site_settings",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(BrushOutline) }),
    },
    {
      label: isPinned ? t("sidebar.menu.unpin") : t("sidebar.menu.pin"),
      key: isPinned ? "unpin" : "pin",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(isPinned ? Star : StarOutline) }),
    },
    {
      label: t("sidebar.menu.refresh"),
      key: "refresh",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(RefreshOutline) }),
    },
    {
      label: t("sidebar.menu.clearCache"),
      key: "clear_cache",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(TrashOutline) }),
    },
    { type: "divider", key: "d1" },
    {
      label: t("sidebar.menu.devtools"),
      key: "devtools",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(ConstructOutline) }),
    },
  ];

  if (!isBuiltin) {
    options.push({ type: "divider", key: "d2" });
    options.push({
      label: t("sidebar.menu.removeSite"),
      key: "remove",
      icon: () => h(NIcon, { size: 18 }, { default: () => h(TrashOutline) }),
    });
  }

  return options;
});

function showContextMenu(event: MouseEvent, site: AiSite) {
  event.preventDefault();
  const sidebar = sidebarEl.value;
  if (!sidebar) return;

  const rect = sidebar.getBoundingClientRect();
  const y = Math.min(Math.max(event.clientY, rect.top + 12), rect.bottom - 12);

  contextMenu.value = {
    show: true,
    x: rect.left + 12,
    y,
    siteId: site.id,
    isBuiltin: site.builtin,
  };
}

function hideContextMenu() {
  contextMenu.value.show = false;
}

async function onContextMenuSelect(key: string) {
  const siteId = contextMenu.value.siteId;
  hideContextMenu();
  if (!siteId) return;

  if (key === "site_settings") return emit("open-site-settings", siteId);
  if (key === "pin") return emit("toggle-pin", siteId, true);
  if (key === "unpin") return emit("toggle-pin", siteId, false);
  if (key === "refresh") return emit("refresh", siteId);
  if (key === "clear_cache") return emit("clear-cache", siteId);
  if (key === "devtools") return emit("devtools", siteId);
  if (key === "remove") return emit("remove-site", siteId);
}

// Drag reorder
const draggedId = ref<string | null>(null);
const dragOverId = ref<string | null>(null);

function onDragStart(event: DragEvent, siteId: string) {
  draggedId.value = siteId;
  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", siteId);
  }
}

function onDragOver(event: DragEvent, siteId: string) {
  event.preventDefault();
  if (draggedId.value && draggedId.value !== siteId) {
    const draggedPinned = pinnedSet.value.has(draggedId.value);
    const targetPinned = pinnedSet.value.has(siteId);
    if (draggedPinned !== targetPinned) return;
    dragOverId.value = siteId;
  }
}

function onDragEnd() {
  draggedId.value = null;
  dragOverId.value = null;
}

function onDrop(event: DragEvent, targetId: string) {
  event.preventDefault();

  if (!draggedId.value || draggedId.value === targetId) {
    onDragEnd();
    return;
  }

  const draggedPinned = pinnedSet.value.has(draggedId.value);
  const targetPinned = pinnedSet.value.has(targetId);
  if (draggedPinned !== targetPinned) {
    onDragEnd();
    return;
  }

  if (draggedPinned) {
    const order = props.pinnedSiteIds.slice();
    const draggedIndex = order.indexOf(draggedId.value);
    const targetIndex = order.indexOf(targetId);
    if (draggedIndex === -1 || targetIndex === -1) {
      onDragEnd();
      return;
    }
    const [removed] = order.splice(draggedIndex, 1);
    order.splice(targetIndex, 0, removed);
    emit("reorder-pinned", order);
    onDragEnd();
    return;
  }

  const currentOrder = [...props.pinnedSites, ...props.unpinnedSites].map((s) => s.id);
  const draggedIndex = currentOrder.indexOf(draggedId.value);
  const targetIndex = currentOrder.indexOf(targetId);
  if (draggedIndex === -1 || targetIndex === -1) {
    onDragEnd();
    return;
  }
  const [removed] = currentOrder.splice(draggedIndex, 1);
  currentOrder.splice(targetIndex, 0, removed);
  emit("reorder-sites", currentOrder);
  onDragEnd();
}
</script>

<template>
  <aside
    ref="sidebarEl"
    class="sidebar"
    :class="{ compact: sidebarWidth <= minSidebarWidth }"
    :style="{ width: sidebarWidth + 'px', minWidth: sidebarWidth + 'px' }"
  >
    <div class="sidebar-header">
      <div class="logo" title="AI Hub">
        <img class="logo-img" :src="appLogo" alt="AI Hub" draggable="false" />
      </div>
    </div>

    <nav class="nav-list">
      <div v-if="sidebarWidth > 100" class="nav-search">
        <n-input v-model:value="search" size="small" :placeholder="t('sidebar.searchPlaceholder')" clearable />
      </div>

      <template v-if="pinnedSites.length">
        <div v-if="sidebarWidth > 100" class="nav-section-title">{{ t("sidebar.sectionPinned") }}</div>
        <button
          v-for="site in pinnedSites"
          :key="`pinned_${site.id}`"
          class="nav-item"
          :class="{ active: currentView === site.id, 'drag-over': dragOverId === site.id }"
          :title="site.name"
          draggable="true"
          @click="emit('switch-site', site.id)"
          @contextmenu="showContextMenu($event, site)"
          @dragstart="onDragStart($event, site.id)"
          @dragover="onDragOver($event, site.id)"
          @drop="onDrop($event, site.id)"
          @dragend="onDragEnd"
        >
          <span class="icon">
            <template v-if="getXiconComponentOrNull(site.icon)">
              <n-icon class="site-xicon" :size="22">
                <component :is="getXiconComponentOrNull(site.icon)!" />
              </n-icon>
            </template>
            <template v-else>
              <img class="icon-img" :src="getIconUrl(site.icon)" :alt="site.name" />
            </template>
          </span>
          <span v-if="sidebarWidth > 100" class="nav-label">{{ site.name }}</span>
          <span v-if="currentView === site.id" class="active-indicator"></span>
        </button>
      </template>

      <template v-if="showRecent && sidebarWidth > 100">
        <div class="nav-section-title">{{ t("sidebar.sectionRecent") }}</div>
        <button
          v-for="site in recentSites.slice(0, 5)"
          :key="`recent_${site.id}`"
          class="nav-item nav-item--recent"
          :class="{ active: currentView === site.id }"
          :title="site.name"
          @click="emit('switch-site', site.id)"
          @contextmenu="showContextMenu($event, site)"
        >
          <span class="icon">
            <template v-if="getXiconComponentOrNull(site.icon)">
              <n-icon class="site-xicon" :size="22">
                <component :is="getXiconComponentOrNull(site.icon)!" />
              </n-icon>
            </template>
            <template v-else>
              <img class="icon-img" :src="getIconUrl(site.icon)" :alt="site.name" />
            </template>
          </span>
          <span class="nav-label">{{ site.name }}</span>
          <span v-if="currentView === site.id" class="active-indicator"></span>
        </button>
      </template>

      <button
        v-for="site in unpinnedSites"
        :key="site.id"
        class="nav-item"
        :class="{ active: currentView === site.id, 'drag-over': dragOverId === site.id }"
        :title="site.name"
        draggable="true"
        @click="emit('switch-site', site.id)"
        @contextmenu="showContextMenu($event, site)"
        @dragstart="onDragStart($event, site.id)"
        @dragover="onDragOver($event, site.id)"
        @drop="onDrop($event, site.id)"
        @dragend="onDragEnd"
      >
        <span class="icon">
          <template v-if="getXiconComponentOrNull(site.icon)">
            <n-icon class="site-xicon" :size="22">
              <component :is="getXiconComponentOrNull(site.icon)!" />
            </n-icon>
          </template>
          <template v-else>
            <img class="icon-img" :src="getIconUrl(site.icon)" :alt="site.name" />
          </template>
        </span>
        <span v-if="sidebarWidth > 100" class="nav-label">{{ site.name }}</span>
        <span v-if="currentView === site.id" class="active-indicator"></span>
      </button>

      <button class="nav-item add-btn" :title="t('sidebar.addSite')" @click="emit('open-add-site')">
        <span class="icon">
          <n-icon class="add-icon" :size="20">
            <add-outline />
          </n-icon>
        </span>
        <span v-if="sidebarWidth > 100" class="nav-label">{{ t("sidebar.addSite") }}</span>
      </button>
    </nav>

    <div class="sidebar-footer">
      <button class="footer-btn settings-btn" @click="emit('open-settings')" :title="t('sidebar.settings')">
        <n-icon class="footer-icon" :size="18">
          <settings-outline />
        </n-icon>
        <span v-if="sidebarWidth > 100" class="footer-label">{{ t("sidebar.settings") }}</span>
      </button>
      <button
        class="footer-btn theme-btn"
        @click="emit('toggle-theme')"
        :title="theme === 'dark' ? t('sidebar.switchToLight') : t('sidebar.switchToDark')"
      >
        <n-icon class="footer-icon" :size="18">
          <sunny-outline v-if="theme === 'dark'" />
          <moon-outline v-else />
        </n-icon>
        <span v-if="sidebarWidth > 100" class="footer-label">{{ theme === "dark" ? t("sidebar.light") : t("sidebar.dark") }}</span>
      </button>
      <button class="footer-btn toggle-btn" @click="emit('toggle-sidebar')" :title="isCollapsed ? t('sidebar.expand') : t('sidebar.collapse')">
        <n-icon class="footer-icon" :size="18">
          <chevron-forward-outline v-if="isCollapsed" />
          <chevron-back-outline v-else />
        </n-icon>
        <span v-if="sidebarWidth > 100" class="footer-label">{{ isCollapsed ? t("sidebar.expand") : t("sidebar.collapse") }}</span>
      </button>
    </div>

    <n-dropdown
      trigger="manual"
      v-model:show="contextMenu.show"
      :x="contextMenu.x"
      :y="contextMenu.y"
      placement="bottom-start"
      :options="contextMenuOptions"
      @select="onContextMenuSelect"
      @clickoutside="hideContextMenu"
    />
  </aside>
</template>

<style scoped>
.sidebar {
  height: 100%;
  background: var(--bg-darker);
  display: flex;
  flex-direction: column;
  border-right: 1px solid var(--border-color);
  z-index: 100;
  transition: none;
}

.sidebar-header {
  padding: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-bottom: 1px solid var(--border-color);
}

.logo {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  background: transparent;
  flex: 0 0 40px;
}

.logo-img {
  width: 40px;
  height: 40px;
  display: block;
  object-fit: cover;
  object-position: center;
  image-rendering: -webkit-optimize-contrast;
}

.nav-list {
  flex: 1;
  padding: 12px 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  overflow-y: auto;
}

.nav-search {
  padding: 4px 4px 10px;
}

.nav-section-title {
  padding: 8px 10px 2px;
  font-size: 12px;
  color: var(--text-secondary);
  opacity: 0.8;
}

.nav-item--recent {
  opacity: 0.9;
}

.nav-item {
  position: relative;
  min-height: 48px;
  padding: 12px;
  border: none;
  border-radius: 12px;
  background: transparent;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 12px;
  transition: all 0.2s ease;
  color: var(--text-secondary);
}

.sidebar.compact .nav-item {
  justify-content: center;
  gap: 0;
}

.nav-item:hover {
  background: var(--hover-bg);
  color: var(--text-primary);
}

.nav-item.active {
  background: var(--active-bg);
  color: var(--accent-color);
}

.nav-item .icon {
  color: var(--text-secondary);
}

.nav-item:hover .icon,
.nav-item.active .icon {
  color: var(--text-secondary);
}

.nav-item.drag-over {
  background: var(--active-bg);
  border: 2px dashed var(--accent-color);
}

.nav-item[draggable="true"] {
  cursor: grab;
}

.nav-item[draggable="true"]:active {
  cursor: grabbing;
}

.icon {
  width: 24px;
  height: 24px;
  min-width: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.site-xicon {
  display: inline-flex;
}

.icon-img {
  width: 100%;
  height: 100%;
  display: block;
}

.nav-label {
  font-size: 14px;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.active-indicator {
  position: absolute;
  left: 0;
  top: 50%;
  transform: translateY(-50%);
  width: 4px;
  height: 24px;
  background: var(--accent-color);
  border-radius: 0 4px 4px 0;
}

.add-btn {
  border: 2px dashed var(--border-color);
  background: transparent;
}

.add-btn:hover {
  border-color: var(--accent-color);
  background: var(--active-bg);
}

.add-icon {
  color: var(--text-secondary);
}

.add-btn:hover .add-icon {
  color: var(--accent-color);
}

.sidebar-footer {
  padding: 12px 8px;
  border-top: 1px solid var(--border-color);
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.footer-btn {
  width: 100%;
  padding: 10px 12px;
  border: none;
  border-radius: 10px;
  background: var(--bg-surface);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  gap: 8px;
  transition: all 0.2s ease;
  font-size: 14px;
}

.sidebar.compact .footer-btn {
  justify-content: center;
}

.footer-btn:hover {
  background: var(--hover-bg);
  color: var(--text-primary);
}

.footer-icon {
  display: inline-flex;
}

.footer-label {
  white-space: nowrap;
}
</style>

<script setup lang="ts">
import { computed } from "vue";
import { NButton, NIcon } from "naive-ui";
import { AddOutline, FlashOutline, SettingsOutline } from "@vicons/ionicons5";

import type { AiSite } from "../types";
import { getIconUrl, getXiconComponentOrNull } from "../composables/useIcons";
import appLogo from "../assets/logo.png";
import { t } from "../i18n";

const props = defineProps<{
  pinnedSites: AiSite[];
  recentSites: AiSite[];
}>();

const emit = defineEmits<{
  (e: "add-site"): void;
  (e: "open-settings"): void;
  (e: "select-site", siteId: string): void;
}>();

const pinnedShown = computed(() => props.pinnedSites.slice(0, 8));
const recentShown = computed(() => props.recentSites.slice(0, 8));

const tips = computed(() => [t("home.tip1"), t("home.tip2"), t("home.tip3")]);

function openSite(siteId: string) {
  emit("select-site", siteId);
}
</script>

<template>
  <main class="home">
    <section class="hero">
      <div class="hero-brand">
        <div class="logo-wrap">
          <img :src="appLogo" alt="AI Hub" draggable="false" />
        </div>
        <div class="brand-copy">
          <p class="eyebrow">{{ t("home.eyebrow") }}</p>
          <h1>{{ t("home.title") }}</h1>
          <p class="subtitle">{{ t("home.subtitle") }}</p>
          <div class="actions">
            <n-button type="primary" size="small" @click="emit('add-site')">
              <template #icon>
                <n-icon><add-outline /></n-icon>
              </template>
              {{ t("home.addSite") }}
            </n-button>
            <n-button quaternary size="small" @click="emit('open-settings')">
              <template #icon>
                <n-icon><settings-outline /></n-icon>
              </template>
              {{ t("home.settings") }}
            </n-button>
          </div>
        </div>
      </div>

      <div class="hero-card">
        <div class="hero-card-header">
          <n-icon size="18"><flash-outline /></n-icon>
          <span>{{ t("home.tipsTitle") }}</span>
        </div>
        <ul>
          <li v-for="tip in tips" :key="tip">{{ tip }}</li>
        </ul>
      </div>
    </section>

    <section class="grid">
      <div class="panel">
        <div class="panel-header">
          <span>{{ t("home.sectionPinned") }}</span>
          <span class="panel-count">{{ pinnedShown.length }}</span>
        </div>
        <div v-if="pinnedShown.length" class="site-list">
          <button v-for="site in pinnedShown" :key="site.id" class="site-card" @click="openSite(site.id)">
            <div class="site-icon">
              <component v-if="getXiconComponentOrNull(site.icon)" :is="getXiconComponentOrNull(site.icon)" />
              <img v-else :src="getIconUrl(site.icon)" :alt="site.name" />
            </div>
            <div class="site-meta">
              <div class="site-name">{{ site.name }}</div>
              <div class="site-url">{{ site.url }}</div>
            </div>
          </button>
        </div>
        <p v-else class="empty">{{ t("home.emptyPinned") }}</p>
      </div>

      <div class="panel">
        <div class="panel-header">
          <span>{{ t("home.sectionRecent") }}</span>
          <span class="panel-count">{{ recentShown.length }}</span>
        </div>
        <div v-if="recentShown.length" class="site-list">
          <button v-for="site in recentShown" :key="site.id" class="site-card" @click="openSite(site.id)">
            <div class="site-icon">
              <component v-if="getXiconComponentOrNull(site.icon)" :is="getXiconComponentOrNull(site.icon)" />
              <img v-else :src="getIconUrl(site.icon)" :alt="site.name" />
            </div>
            <div class="site-meta">
              <div class="site-name">{{ site.name }}</div>
              <div class="site-url">{{ site.url }}</div>
            </div>
          </button>
        </div>
        <p v-else class="empty">{{ t("home.emptyRecent") }}</p>
      </div>
    </section>
  </main>
</template>

<style scoped>
.home {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 24px;
  padding: 24px 28px 32px;
  background:
    radial-gradient(1200px 480px at 18% 10%, rgba(90, 169, 230, 0.16), transparent 60%),
    radial-gradient(900px 360px at 85% 0%, rgba(137, 180, 250, 0.12), transparent 60%),
    var(--bg-dark);
  color: var(--text-primary);
  overflow: auto;
}

.hero {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(240px, 0.8fr);
  gap: 20px;
  align-items: stretch;
}

.hero-brand {
  display: flex;
  gap: 18px;
  padding: 18px 20px;
  border-radius: 18px;
  background: color-mix(in srgb, var(--bg-surface) 70%, transparent);
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
  box-shadow: 0 10px 28px rgba(0, 0, 0, 0.18);
  backdrop-filter: blur(10px);
}

.logo-wrap {
  width: 64px;
  height: 64px;
  padding: 10px;
  border-radius: 16px;
  background: linear-gradient(135deg, rgba(90, 169, 230, 0.18), rgba(203, 166, 247, 0.2));
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
  display: flex;
  align-items: center;
  justify-content: center;
}

.logo-wrap img {
  width: 100%;
  height: 100%;
  object-fit: contain;
}

.brand-copy {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.eyebrow {
  text-transform: uppercase;
  font-size: 11px;
  letter-spacing: 0.2em;
  color: var(--text-secondary);
}

.brand-copy h1 {
  font-size: 24px;
  font-weight: 600;
}

.subtitle {
  color: var(--text-secondary);
  font-size: 13px;
  line-height: 1.5;
}

.actions {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.hero-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 18px;
  border-radius: 18px;
  background: color-mix(in srgb, var(--bg-darker) 80%, transparent);
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
}

.hero-card-header {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 13px;
  color: var(--text-secondary);
}

.hero-card ul {
  display: grid;
  gap: 8px;
  list-style: none;
  font-size: 13px;
  color: var(--text-primary);
}

.hero-card li {
  padding: 8px 10px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--bg-surface) 70%, transparent);
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 18px;
}

.panel {
  padding: 16px;
  border-radius: 16px;
  background: color-mix(in srgb, var(--bg-surface) 85%, transparent);
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 13px;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.12em;
}

.panel-count {
  font-size: 11px;
  padding: 2px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--accent-color) 25%, transparent);
  color: var(--text-primary);
}

.site-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.site-card {
  display: flex;
  gap: 12px;
  align-items: center;
  padding: 10px 12px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--bg-darker) 80%, transparent);
  border: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
  color: inherit;
  cursor: pointer;
  text-align: left;
}

.site-card:hover {
  border-color: color-mix(in srgb, var(--accent-color) 50%, var(--border-color));
}

.site-icon {
  width: 36px;
  height: 36px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--bg-surface) 80%, transparent);
}

.site-icon img {
  width: 20px;
  height: 20px;
  object-fit: contain;
}

.site-icon :deep(svg) {
  width: 20px;
  height: 20px;
  color: var(--text-primary);
}

.site-meta {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.site-name {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.site-url {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.empty {
  font-size: 13px;
  color: var(--text-secondary);
}

@media (max-width: 900px) {
  .hero {
    grid-template-columns: 1fr;
  }
}
</style>

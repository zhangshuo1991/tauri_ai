<script setup lang="ts">
import type { Component } from "vue";
import { computed, ref, watch } from "vue";
import { NButton, NIcon, NInput } from "naive-ui";

import { fileToSquarePngDataUrl, getIconTitle, getIconUrl, getXiconComponentOrNull, xiconOptions, type XiconKey } from "../composables/useIcons";

const props = defineProps<{
  modelValue: string;
}>();

const emit = defineEmits<{
  (e: "update:modelValue", value: string): void;
  (e: "error", message: string): void;
}>();

const source = ref<"upload" | "xicons">(props.modelValue.startsWith("data:image/") ? "upload" : "xicons");
const search = ref<string>("");
const uploadInputEl = ref<HTMLInputElement | null>(null);

watch(
  () => props.modelValue,
  (next) => {
    if (next.startsWith("data:image/")) source.value = "upload";
  },
);

const filteredXiconOptions = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return xiconOptions;
  return xiconOptions.filter((o) => o.label.toLowerCase().includes(q) || o.key.toLowerCase().includes(q));
});

function selectXicon(key: XiconKey) {
  emit("update:modelValue", key);
  source.value = "xicons";
}

function triggerUpload() {
  uploadInputEl.value?.click();
}

async function onUploadChange(event: Event) {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0] ?? null;
  if (!file) return;

  if (file.type === "image/svg+xml") {
    emit("error", "暂不支持 SVG，请上传 PNG/JPG/WebP/GIF");
    input.value = "";
    return;
  }

  const MAX_ICON_BYTES = 512 * 1024;
  if (file.size > MAX_ICON_BYTES) {
    emit("error", "图片过大（最大 512KB）");
    input.value = "";
    return;
  }

  try {
    const pngDataUrl = await fileToSquarePngDataUrl(file, 64);
    emit("update:modelValue", pngDataUrl);
    source.value = "upload";
  } catch (e) {
    console.error("处理上传图标失败:", e);
    emit("error", "处理图片失败");
  } finally {
    input.value = "";
  }
}

function iconComponent(icon: string): Component | null {
  return getXiconComponentOrNull(icon);
}
</script>

<template>
  <div class="icon-form">
    <div class="icon-row">
      <div class="icon-preview" :title="getIconTitle(modelValue)">
        <template v-if="iconComponent(modelValue)">
          <n-icon :size="22">
            <component :is="iconComponent(modelValue)!" />
          </n-icon>
        </template>
        <template v-else>
          <img class="icon-img" :src="getIconUrl(modelValue)" alt="icon preview" />
        </template>
      </div>

      <div class="icon-source">
        <button type="button" class="icon-source-btn" :class="{ active: source === 'upload' }" @click="source = 'upload'">
          上传图片
        </button>
        <button type="button" class="icon-source-btn" :class="{ active: source === 'xicons' }" @click="source = 'xicons'">
          Xicons
        </button>
      </div>
    </div>

    <div v-if="source === 'upload'" class="icon-panel">
      <input ref="uploadInputEl" type="file" accept="image/*" class="hidden-input" @change="onUploadChange" />
      <n-button @click="triggerUpload">选择图片</n-button>
      <div class="hint">将自动裁剪为正方形并压缩为 PNG（64×64）。</div>
    </div>

    <div v-else class="icon-panel">
      <n-input v-model:value="search" placeholder="搜索图标（例如：chat / web / code）" />
      <div class="xicon-grid">
        <button
          v-for="opt in filteredXiconOptions"
          :key="opt.key"
          type="button"
          class="xicon-option"
          :class="{ selected: modelValue === opt.key }"
          @click="selectXicon(opt.key)"
        >
          <n-icon :size="20">
            <component :is="iconComponent(opt.key)!" />
          </n-icon>
          <span class="xicon-label">{{ opt.label }}</span>
        </button>
      </div>
      <div class="hint">当前仅内置少量 `@vicons/ionicons5` 图标；需要更多我可以继续扩充列表或接入更多包。</div>
    </div>
  </div>
</template>

<style scoped>
.icon-form {
  width: 100%;
}

.icon-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.icon-preview {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: var(--bg-surface);
  border: 1px solid var(--border-color);
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.icon-source {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.icon-source-btn {
  padding: 8px 10px;
  border-radius: 10px;
  border: 1px solid var(--border-color);
  background: transparent;
  color: var(--text-primary);
  cursor: pointer;
}

.icon-source-btn.active {
  border-color: var(--accent-color);
  background: var(--active-bg);
}

.icon-panel {
  margin-top: 10px;
}

.hidden-input {
  display: none;
}

.xicon-grid {
  margin-top: 10px;
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}

.xicon-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px;
  border-radius: 12px;
  border: 1px solid var(--border-color);
  background: var(--bg-surface);
  color: var(--text-primary);
  cursor: pointer;
}

.xicon-option.selected {
  border-color: var(--accent-color);
  background: var(--active-bg);
}

.xicon-label {
  font-size: 12px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.hint {
  margin-top: 8px;
  font-size: 12px;
  color: var(--text-secondary);
  line-height: 1.4;
}

.icon-img {
  width: 100%;
  height: 100%;
  display: block;
}
</style>


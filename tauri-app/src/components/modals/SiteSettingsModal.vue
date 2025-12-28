<script setup lang="ts">
import { ref, watch } from "vue";
import { NButton, NCard, NForm, NFormItem, NInput, NModal, NSpace, NText } from "naive-ui";

import IconPicker from "../IconPicker.vue";
import { t } from "../../i18n";

const props = defineProps<{
  site: { id: string; name: string; url: string; icon: string; summary_prompt_override?: string } | null;
}>();

const show = defineModel<boolean>("show", { required: true });

const emit = defineEmits<{
  (e: "submit", value: { id: string; name: string; url: string; icon: string; summary_prompt_override: string }): void;
  (e: "error", message: string): void;
}>();

const form = ref<{ id: string; name: string; url: string; icon: string; summary_prompt_override: string } | null>(null);

watch(
  () => props.site,
  (next) => {
    if (next) form.value = { ...next, summary_prompt_override: next.summary_prompt_override ?? "" };
  },
  { immediate: true },
);

watch(
  () => show.value,
  (open) => {
    if (open && props.site) {
      form.value = { ...props.site, summary_prompt_override: props.site.summary_prompt_override ?? "" };
    }
  },
);

function onSubmit() {
  if (!form.value) return;
  emit("submit", { ...form.value });
}

function clearOverride() {
  if (!form.value) return;
  form.value.summary_prompt_override = "";
}
</script>

<template>
  <n-modal v-model:show="show" :mask-closable="true" :close-on-esc="true">
    <n-card
      :title="form ? `${t('siteSettings.title')} - ${form.name}` : t('siteSettings.title')"
      closable
      style="width: 560px"
      @close="show = false"
    >
      <n-form v-if="form" label-placement="left" label-width="80">
        <n-form-item :label="t('siteSettings.name')">
          <n-input v-model:value="form.name" placeholder="Claude" />
        </n-form-item>
        <n-form-item :label="t('siteSettings.url')">
          <n-input v-model:value="form.url" placeholder="https://claude.ai" />
        </n-form-item>
        <n-form-item :label="t('siteSettings.icon')">
          <icon-picker v-model="form.icon" @error="(m) => emit('error', m)" />
        </n-form-item>

        <n-form-item :label="t('siteSettings.summaryPromptOverride')">
          <n-space vertical size="small" style="width: 100%">
            <n-input
              v-model:value="form.summary_prompt_override"
              type="textarea"
              :autosize="{ minRows: 4, maxRows: 10 }"
              :placeholder="t('settings.summaryPromptHint', { language: '{language}', text: '{text}' })"
            />
            <div style="display: flex; justify-content: space-between; align-items: center">
              <n-text depth="3" style="font-size: 12px">{{ t("settings.summaryPromptHint", { language: "{language}", text: "{text}" }) }}</n-text>
              <n-button size="tiny" @click="clearOverride">{{ t("siteSettings.useGlobalPrompt") }}</n-button>
            </div>
          </n-space>
        </n-form-item>
      </n-form>
      <template #footer>
        <div class="modal-footer">
          <n-button @click="show = false">{{ t("settings.cancel") }}</n-button>
          <n-button type="primary" @click="onSubmit">{{ t("settings.save") }}</n-button>
        </div>
      </template>
    </n-card>
  </n-modal>
</template>

<style scoped>
.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
}
</style>

<script setup lang="ts">
import { computed } from "vue";
import { createDiscreteApi, NButton, NCard, NInput, NModal, NSpace } from "naive-ui";
import { t } from "../../i18n";

const props = defineProps<{
  show: boolean;
  summary: string;
}>();

const emit = defineEmits<{
  (e: "update:show", value: boolean): void;
  (e: "update:summary", value: string): void;
}>();

const { message } = createDiscreteApi(["message"]);

const canCopy = computed(() => props.summary.trim().length > 0);

async function copy() {
  if (!canCopy.value) return;
  try {
    const text = `${t("summary.copyPrefix")}\n${props.summary.trim()}\n\n${t("summary.nextQuestion")}`;
    await navigator.clipboard.writeText(text);
    message.success(t("summary.copySuccess"));
  } catch {
    message.error(t("summary.copyFail"));
  }
}
</script>

<template>
  <n-modal :show="show" :mask-closable="true" :close-on-esc="true" @update:show="(v) => emit('update:show', v)">
    <n-card
      :title="t('summary.title')"
      closable
      :bordered="false"
      size="large"
      :segmented="{ footer: 'soft' }"
      :content-style="{ maxHeight: 'calc(100vh - 220px)', overflow: 'auto' }"
      style="width: 820px; max-width: calc(100vw - 32px)"
      @close="emit('update:show', false)"
    >
      <n-space vertical size="large">
        <n-input
          :value="summary"
          type="textarea"
          :autosize="{ minRows: 10, maxRows: 22 }"
          :placeholder="t('summary.placeholder')"
          @update:value="(v) => emit('update:summary', v)"
        />
      </n-space>

      <template #footer>
        <div style="display: flex; justify-content: flex-end; gap: 10px">
          <n-button @click="emit('update:show', false)">{{ t("common.close") }}</n-button>
          <n-button type="primary" :disabled="!canCopy" @click="copy">{{ t("common.copyToClipboard") }}</n-button>
        </div>
      </template>
    </n-card>
  </n-modal>
</template>

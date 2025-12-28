<script setup lang="ts">
import { ref, watch } from "vue";
import { NButton, NCard, NForm, NFormItem, NInput, NModal } from "naive-ui";

import IconPicker from "../IconPicker.vue";
import { t } from "../../i18n";

const show = defineModel<boolean>("show", { required: true });

const emit = defineEmits<{
  (e: "submit", value: { name: string; url: string; icon: string }): void;
  (e: "error", message: string): void;
}>();

const form = ref<{ name: string; url: string; icon: string }>({ name: "", url: "", icon: "custom" });

watch(
  () => show.value,
  (open) => {
    if (open) {
      form.value = { name: "", url: "", icon: "custom" };
    }
  },
);

function onSubmit() {
  emit("submit", { ...form.value });
}
</script>

<template>
  <n-modal v-model:show="show" :mask-closable="true" :close-on-esc="true">
    <n-card :title="t('addSite.title')" closable style="width: 520px" @close="show = false">
      <n-form label-placement="left" label-width="80">
        <n-form-item :label="t('siteSettings.name')">
          <n-input v-model:value="form.name" placeholder="例如：Claude" />
        </n-form-item>
        <n-form-item :label="t('siteSettings.url')">
          <n-input v-model:value="form.url" placeholder="例如：https://claude.ai" />
        </n-form-item>
        <n-form-item :label="t('siteSettings.icon')">
          <icon-picker v-model="form.icon" @error="(m) => emit('error', m)" />
        </n-form-item>
      </n-form>
      <template #footer>
        <div class="modal-footer">
          <n-button @click="show = false">{{ t('settings.cancel') }}</n-button>
          <n-button type="primary" @click="onSubmit">{{ t('addSite.add') }}</n-button>
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

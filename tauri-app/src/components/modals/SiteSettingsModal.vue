<script setup lang="ts">
import { ref, watch } from "vue";
import { NButton, NCard, NForm, NFormItem, NInput, NModal } from "naive-ui";

import IconPicker from "../IconPicker.vue";

const props = defineProps<{
  site: { id: string; name: string; url: string; icon: string } | null;
}>();

const show = defineModel<boolean>("show", { required: true });

const emit = defineEmits<{
  (e: "submit", value: { id: string; name: string; url: string; icon: string }): void;
  (e: "error", message: string): void;
}>();

const form = ref<{ id: string; name: string; url: string; icon: string } | null>(null);

watch(
  () => props.site,
  (next) => {
    if (next) form.value = { ...next };
  },
  { immediate: true },
);

watch(
  () => show.value,
  (open) => {
    if (open && props.site) {
      form.value = { ...props.site };
    }
  },
);

function onSubmit() {
  if (!form.value) return;
  emit("submit", { ...form.value });
}
</script>

<template>
  <n-modal v-model:show="show" :mask-closable="true" :close-on-esc="true">
    <n-card :title="form ? `站点设置 - ${form.name}` : '站点设置'" closable style="width: 520px" @close="show = false">
      <n-form v-if="form" label-placement="left" label-width="80">
        <n-form-item label="站点名称">
          <n-input v-model:value="form.name" placeholder="例如：Claude" />
        </n-form-item>
        <n-form-item label="站点 URL">
          <n-input v-model:value="form.url" placeholder="例如：https://claude.ai" />
        </n-form-item>
        <n-form-item label="图标">
          <icon-picker v-model="form.icon" @error="(m) => emit('error', m)" />
        </n-form-item>
      </n-form>
      <template #footer>
        <div class="modal-footer">
          <n-button @click="show = false">取消</n-button>
          <n-button type="primary" @click="onSubmit">保存</n-button>
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


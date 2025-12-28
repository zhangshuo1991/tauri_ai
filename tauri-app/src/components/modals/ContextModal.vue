<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { createDiscreteApi, NButton, NCard, NDivider, NForm, NFormItem, NInput, NModal, NSelect, NSpace, NSpin } from "naive-ui";

import type { ProjectContext, ProjectSummary } from "../../types";

const props = defineProps<{
  show: boolean;
  activeProjectId: string;
}>();

const emit = defineEmits<{
  (e: "update:show", value: boolean): void;
  (e: "update:activeProjectId", value: string): void;
}>();

const { message, dialog } = createDiscreteApi(["message", "dialog"]);

const projects = ref<ProjectSummary[]>([]);
const selectedProjectId = ref<string>("");
const loading = ref(false);
const saving = ref(false);
const summarizing = ref(false);

const showCreate = ref(false);
const newProjectTitle = ref("");

const title = ref("");
const notes = ref("");
const summary = ref("");

const projectOptions = computed(() => projects.value.map((p) => ({ label: p.title, value: p.id })));

async function refreshProjects() {
  projects.value = await invoke<ProjectSummary[]>("list_projects");
}

async function loadProject(projectId: string) {
  if (!projectId) return;
  loading.value = true;
  try {
    const p = await invoke<ProjectContext>("get_project", { projectId });
    title.value = p.title;
    notes.value = p.notes;
    summary.value = p.summary;
  } finally {
    loading.value = false;
  }
}

async function ensureDefaultProject() {
  await refreshProjects();
  if (!projects.value.length) {
    const id = await invoke<string>("create_project", { title: "默认项目" });
    await refreshProjects();
    selectedProjectId.value = id;
    emit("update:activeProjectId", id);
    await invoke("set_active_project", { projectId: id });
    await loadProject(id);
  }
}

async function changeProject(projectId: string) {
  selectedProjectId.value = projectId;
  emit("update:activeProjectId", projectId);
  await invoke("set_active_project", { projectId });
  await loadProject(projectId);
}

async function createProject() {
  newProjectTitle.value = "";
  showCreate.value = true;
}

async function confirmCreateProject() {
  const t = newProjectTitle.value.trim() || "默认项目";
  const id = await invoke<string>("create_project", { title: t });
  await refreshProjects();
  await changeProject(id);
  showCreate.value = false;
  message.success("已创建项目");
}

async function deleteCurrentProject() {
  const id = selectedProjectId.value;
  if (!id) return;
  dialog.warning({
    title: "删除项目",
    content: "确认删除该项目？内容将无法恢复。",
    positiveText: "删除",
    negativeText: "取消",
    onPositiveClick: async () => {
      await invoke("delete_project", { projectId: id });
      await refreshProjects();
      const next = projects.value[0]?.id ?? "";
      selectedProjectId.value = next;
      emit("update:activeProjectId", next);
      await invoke("set_active_project", { projectId: next });
      if (next) {
        await loadProject(next);
      } else {
        title.value = "";
        notes.value = "";
        summary.value = "";
      }
      message.success("已删除项目");
    },
  });
}

async function saveProject() {
  const id = selectedProjectId.value;
  if (!id) return;
  saving.value = true;
  try {
    await invoke("update_project", {
      projectId: id,
      title: title.value,
      notes: notes.value,
      summary: summary.value,
    });
    await refreshProjects();
    message.success("已保存");
  } finally {
    saving.value = false;
  }
}

async function summarize() {
  if (!notes.value.trim()) {
    message.warning("请先粘贴对话/素材到“项目笔记”");
    return;
  }
  summarizing.value = true;
  try {
    const result = await invoke<string>("summarize_text", { text: notes.value });
    summary.value = result;
    await saveProject();
  } catch (e: any) {
    message.error(String(e));
  } finally {
    summarizing.value = false;
  }
}

function buildCarryPrompt(): string {
  const t = title.value.trim() ? `项目：${title.value.trim()}\n\n` : "";
  const base = summary.value.trim() ? summary.value.trim() : notes.value.trim();
  return `${t}上下文（可迁移）：\n${base}\n\n接下来我想问：<在此写问题>`;
}

async function copyToClipboard() {
  const text = buildCarryPrompt();
  try {
    await navigator.clipboard.writeText(text);
    message.success("已复制到剪贴板");
  } catch (e) {
    message.error("复制失败（可能缺少剪贴板权限）");
  }
}

watch(
  () => props.show,
  async (open) => {
    if (!open) return;
    selectedProjectId.value = props.activeProjectId;
    await ensureDefaultProject();
    if (!selectedProjectId.value) {
      selectedProjectId.value = props.activeProjectId || projects.value[0]?.id || "";
    }
    if (selectedProjectId.value) {
      await loadProject(selectedProjectId.value);
    }
  },
  { immediate: true },
);
</script>

<template>
  <n-modal :show="show" :mask-closable="true" :close-on-esc="true" @update:show="(v) => emit('update:show', v)">
    <n-card
      title="上下文（按项目）"
      closable
      :bordered="false"
      size="large"
      :segmented="{ content: 'soft', footer: 'soft' }"
      style="width: 860px; max-width: calc(100vw - 32px)"
      @close="emit('update:show', false)"
    >
      <n-space vertical size="large">
        <div style="display: flex; align-items: center; gap: 10px; flex-wrap: wrap">
          <n-select
            style="width: 260px"
            :options="projectOptions"
            :value="selectedProjectId"
            placeholder="选择项目"
            @update:value="(v) => changeProject(v as string)"
          />
          <n-button secondary @click="createProject">新建项目</n-button>
          <n-button tertiary type="error" :disabled="!selectedProjectId" @click="deleteCurrentProject">删除项目</n-button>
          <div style="flex: 1"></div>
          <n-button :loading="saving" :disabled="!selectedProjectId" @click="saveProject">保存</n-button>
          <n-button type="primary" :loading="summarizing" :disabled="!selectedProjectId" @click="summarize">自动总结</n-button>
          <n-button tertiary :disabled="!selectedProjectId" @click="copyToClipboard">复制到剪贴板</n-button>
        </div>

        <n-divider title-placement="left">项目内容</n-divider>

        <n-spin :show="loading">
          <n-form label-placement="left" label-width="110">
            <n-form-item label="项目名称">
              <n-input v-model:value="title" placeholder="例如：XXX 需求讨论 / 论文阅读 / Bug 排查" />
            </n-form-item>
            <n-form-item label="项目笔记">
              <n-input
                v-model:value="notes"
                type="textarea"
                :autosize="{ minRows: 8, maxRows: 16 }"
                placeholder="把多轮对话/背景资料粘贴到这里，然后点“自动总结”。"
              />
            </n-form-item>
            <n-form-item label="可迁移摘要">
              <n-input v-model:value="summary" type="textarea" :autosize="{ minRows: 6, maxRows: 12 }" placeholder="自动总结结果会出现在这里（也可手动编辑）。" />
            </n-form-item>
          </n-form>
        </n-spin>
      </n-space>
    </n-card>
  </n-modal>

  <n-modal v-model:show="showCreate" :mask-closable="true" :close-on-esc="true">
    <n-card title="新建项目" closable style="width: 420px; max-width: calc(100vw - 32px)" @close="showCreate = false">
      <n-form label-placement="left" label-width="90">
        <n-form-item label="项目名称">
          <n-input v-model:value="newProjectTitle" placeholder="例如：需求讨论 / Bug 排查 / 论文阅读" />
        </n-form-item>
      </n-form>
      <template #footer>
        <div style="display: flex; justify-content: flex-end; gap: 10px">
          <n-button @click="showCreate = false">取消</n-button>
          <n-button type="primary" @click="confirmCreateProject">创建</n-button>
        </div>
      </template>
    </n-card>
  </n-modal>
</template>

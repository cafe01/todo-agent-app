<script setup lang="ts">
import { computed, ref } from 'vue';
import type { Task } from './contracts';
import { useTasks } from './useTasks';
import { TasksApi } from './api';

const token = sessionStorage.getItem('todo-agent-token');
const tasksState = useTasks(new TasksApi(token ?? ''));
const { tasks, connected, error, loading, pendingCreate, pendingTaskIds, create, update, remove } = tasksState;
const draft = ref('');
const filter = ref<'all' | 'open' | 'done'>('all');
const editingId = ref<string | null>(null);
const editDraft = ref('');
const remaining = computed(() => tasks.value.filter((task) => !task.completed).length);
const filteredTasks = computed(() => tasks.value.filter((task) => {
  return filter.value === 'all' || (filter.value === 'open' ? !task.completed : task.completed);
}));

async function addTask() {
  const title = draft.value.trim();
  if (!title) return;
  await create(title);
  if (!error.value) draft.value = '';
}

function startEdit(task: Task) {
  editingId.value = task.id;
  editDraft.value = task.title;
}

async function saveEdit(task: Task) {
  const title = editDraft.value.trim();
  if (!title) return;
  await update(task, { title });
  if (!error.value) editingId.value = null;
}

function cancelEdit() { editingId.value = null; }
</script>

<template>
  <main class="page-shell">
    <header class="topbar">
      <a class="brand" href="#" aria-label="Hoje, início">
        <span class="brand-mark" aria-hidden="true">h.</span>
        <span>hoje<span class="brand-period">.</span></span>
      </a>
      <div class="connection" :class="connected ? 'is-connected' : 'is-offline'" role="status">
        <span class="connection-dot" aria-hidden="true"></span>
        {{ connected ? 'Sincronizado' : 'Reconectando' }}
      </div>
    </header>

    <section class="workspace" aria-labelledby="page-title">
      <div class="intro">
        <p class="eyebrow">SEU ESPAÇO, EM ORDEM</p>
        <h1 id="page-title">Um passo de<br /><span>cada vez.</span></h1>
        <p class="intro-copy">Uma lista simples para tirar as ideias da cabeça e colocar o dia em movimento.</p>
      </div>

      <section class="task-panel" aria-label="Lista de tarefas">
        <div class="panel-heading">
          <div>
            <h2>Minhas tarefas</h2>
            <p>{{ remaining === 0 ? 'Tudo em dia por aqui.' : `${remaining} ${remaining === 1 ? 'pendente' : 'pendentes'}` }}</p>
          </div>
          <span class="task-count" aria-label="Total de tarefas">{{ tasks.length.toString().padStart(2, '0') }}</span>
        </div>

        <form class="create-form" @submit.prevent="addTask">
          <span class="plus" aria-hidden="true">+</span>
          <input v-model="draft" aria-label="Nova tarefa" placeholder="O que você precisa fazer?" maxlength="200" :disabled="!connected || pendingCreate" />
          <button class="add-button" type="submit" :disabled="!connected || pendingCreate || !draft.trim()">{{ pendingCreate ? 'Salvando…' : 'Adicionar' }}</button>
        </form>

        <div class="list-toolbar">
          <span class="list-label">LISTA</span>
          <div class="filters" aria-label="Filtrar tarefas">
            <button v-for="option in ([['all', 'Todas'], ['open', 'A fazer'], ['done', 'Feitas']] as const)" :key="option[0]" type="button" :class="{ active: filter === option[0] }" @click="filter = option[0]">{{ option[1] }}</button>
          </div>
        </div>

        <div v-if="loading && tasks.length === 0" class="empty-state">
          <span class="loader" aria-hidden="true"></span>
          <p>Carregando suas tarefas…</p>
        </div>
        <div v-else-if="filteredTasks.length === 0" class="empty-state">
          <span class="empty-icon" aria-hidden="true">✳</span>
          <p>{{ tasks.length === 0 ? 'Sua lista começa com uma ideia.' : 'Nada por aqui neste filtro.' }}</p>
          <span>{{ tasks.length === 0 ? 'Adicione uma tarefa acima para começar.' : 'Experimente outra opção.' }}</span>
        </div>
        <ul v-else class="task-list">
          <li v-for="task in filteredTasks" :key="task.id" class="task-row" :class="{ completed: task.completed }">
            <button class="check-button" :aria-label="task.completed ? `Marcar ${task.title} como pendente` : `Concluir ${task.title}`" :disabled="!connected || pendingTaskIds.has(task.id)" @click="update(task, { completed: !task.completed })">
              <span v-if="task.completed" aria-hidden="true">✓</span>
            </button>
            <form v-if="editingId === task.id" class="edit-form" @submit.prevent="saveEdit(task)">
              <input v-model="editDraft" :aria-label="`Editar ${task.title}`" maxlength="200" autofocus :disabled="!connected || pendingTaskIds.has(task.id)" />
              <button class="icon-action save-action" type="submit" aria-label="Salvar edição" :disabled="!connected || pendingTaskIds.has(task.id) || !editDraft.trim()">✓</button>
              <button class="icon-action" type="button" aria-label="Cancelar edição" @click="cancelEdit">×</button>
            </form>
            <template v-else>
              <span class="task-title">{{ task.title }}</span>
              <div class="row-actions">
                <button class="icon-action" type="button" :aria-label="`Editar ${task.title}`" :disabled="!connected || pendingTaskIds.has(task.id)" @click="startEdit(task)">✎</button>
                <button class="icon-action delete-action" type="button" :aria-label="`Excluir ${task.title}`" :disabled="!connected || pendingTaskIds.has(task.id)" @click="remove(task)">×</button>
              </div>
            </template>
          </li>
        </ul>
        <div v-if="error" class="error-banner" role="alert"><span aria-hidden="true">!</span>{{ error }}</div>
        <div v-if="!connected" class="offline-note"><span aria-hidden="true">↻</span> As tarefas ficam visíveis enquanto a conexão volta. Edições estão pausadas.</div>
        <footer class="panel-footer"><span><i aria-hidden="true"></i> Suas tarefas, sempre atualizadas</span><span>TO DO AGENT APP</span></footer>
      </section>
    </section>

    <footer class="page-footer"><span>Feito para focar no que importa.</span><span>✳</span></footer>
  </main>
</template>

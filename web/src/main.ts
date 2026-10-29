import { createApp } from 'vue';
import App from './App.vue';
import { bootstrapToken } from './contracts';
import './style.css';

const token = bootstrapToken();
if (!token) {
  document.querySelector<HTMLDivElement>('#app')!.innerHTML = '<main class="auth-error"><span>h.</span><h1>Link de acesso inválido</h1><p>Abra o endereço fornecido pelo To Do Agent para conectar sua lista.</p></main>';
} else {
  createApp(App).mount('#app');
}

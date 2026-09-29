//========================================
// admin.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================
import { dataService } from '../data.js';
import { DashboardAuth } from '../auth.js';
import { updateAllIcons } from '../app.js';

let usuarios = [];

export async function renderAdminPage(appRoot) {
  appRoot.innerHTML = `
    <div class="container">
      <div class="card">
        <h3><img class="icon section-icon" data-icon="material-symbols:admin-panel-settings" alt=""> Gerenciamento de Usuarios</h3>
        <p style="color:var(--text-secondary);margin-bottom:20px">Ambiente local: usuario padrao disponivel.</p>
        <div class="table-wrapper">
          <table class="admin-table">
            <thead>
              <tr><th>Email</th><th>Nome</th><th>Role</th><th>Criado em</th><th>Acoes</th></tr>
            </thead>
            <tbody id="users-tbody"></tbody>
          </table>
        </div>
      </div>
    </div>
  `;

  await loadUsers();
  updateAllIcons();
}

async function loadUsers() {
  try {
    usuarios = await dataService.fetchUsuarios();
  } catch (e) {
    console.error('[Admin] Erro ao carregar usuarios:', e);
    usuarios = [];
  }
  renderUsersTable();
}

function renderUsersTable() {
  const tbody = document.getElementById('users-tbody');
  if (!tbody) return;
  tbody.innerHTML = '';

  if (usuarios.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-secondary)">Nenhum usuario encontrado.</td></tr>';
    return;
  }

  usuarios.forEach(u => {
    const tr = document.createElement('tr');
    const dataCriacao = u.created_at
      ? new Date(u.created_at).toLocaleDateString('pt-BR')
      : new Date().toLocaleDateString('pt-BR');
    tr.innerHTML = `
      <td>${u.email}</td>
      <td>${u.nome || '-'}</td>
      <td><span class="role-badge ${u.role}">${u.role}</span></td>
      <td>${dataCriacao}</td>
      <td><span style="color:var(--text-secondary);font-size:12px">-</span></td>
    `;
    tbody.appendChild(tr);
  });
}

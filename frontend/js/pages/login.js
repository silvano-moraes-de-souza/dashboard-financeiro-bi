//========================================
// login.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================
import { DashboardAuth } from '../auth.js';
import { router } from '../router.js';
import { updateAllIcons } from '../app.js';

export async function renderLoginPage(appRoot) {
  appRoot.innerHTML = `
    <div id="auth-container">
      <div class="logo">
        <img class="logo-img" src="https://i.ibb.co/TxRDrPN2/logo-Dashboard.png" alt="Dashboard Financeiro BI">
      </div>
      <form id="login-form">
        <h2>Acesso ao Sistema</h2>
        <div class="input-group">
          <label for="email">Email</label>
          <input type="email" id="email" required autocomplete="email" placeholder="email@exemplo.com">
        </div>
        <div class="input-group">
          <label for="password">Senha</label>
          <div class="password-wrapper">
            <input type="password" id="password" required autocomplete="current-password" placeholder="Sua senha">
            <button type="button" class="password-toggle" id="passwordToggle" tabindex="-1" aria-label="Mostrar senha">
              <img class="icon password-eye" data-icon="material-symbols:visibility" alt="">
              <img class="icon password-eye-off" data-icon="material-symbols:visibility-off" alt="" style="display:none">
            </button>
          </div>
        </div>
        <button type="submit" class="btn-primary" id="btn-login">Entrar</button>
        <div id="error-msg" class="error-container"></div>
      </form>
      <footer style="text-align: center; margin-top: 25px; font-family: 'Inter', sans-serif; font-size: 11px; color: #475569; letter-spacing: 0.3px; line-height: 1.6;">
        Desenvolvido por: <strong>Silvano Moraes de Souza</strong><br>
        <span style="color: #64748b; font-size: 10px; font-weight: 500;">Especialista em Engenharia de Dados, Programação, Governança de DBA e Cibersegurança Corporativa</span>
      </footer>
    </div>
  `;

  const form = document.getElementById('login-form');
  const errorContainer = document.getElementById('error-msg');
  const btnLogin = document.getElementById('btn-login');

  const passwordInput = document.getElementById('password');
  const passwordToggle = document.getElementById('passwordToggle');
  const eyeIcon = passwordToggle?.querySelector('.password-eye');
  const eyeOffIcon = passwordToggle?.querySelector('.password-eye-off');
  if (passwordToggle) {
    passwordToggle.addEventListener('click', () => {
      const isPassword = passwordInput.type === 'password';
      passwordInput.type = isPassword ? 'text' : 'password';
      if (eyeIcon) eyeIcon.style.display = isPassword ? 'none' : '';
      if (eyeOffIcon) eyeOffIcon.style.display = isPassword ? '' : 'none';
    });
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    errorContainer.innerText = '';
    btnLogin.disabled = true;
    btnLogin.textContent = 'Entrando...';

    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    try {
      await DashboardAuth.login(email, password);
      router.navigate('/financeiro');
    } catch (error) {
      console.error('Login failed:', error);
      errorContainer.innerText = `Erro ao entrar: ${error.message}`;
    } finally {
      btnLogin.disabled = false;
      btnLogin.textContent = 'Entrar';
    }
  });

  updateAllIcons();
}

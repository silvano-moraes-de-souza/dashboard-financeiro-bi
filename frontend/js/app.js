//========================================
// app.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================
import { DashboardAuth } from './auth.js';
import { router } from './router.js';

const ICONIFY_BASE = 'https://api.iconify.design';

function getIconColor() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? '34D399' : '10B981';
}

function iconUrl(name, color) {
  return `${ICONIFY_BASE}/${name}.svg?color=%23${color}`;
}

function updateAllIcons() {
  const color = getIconColor();
  document.querySelectorAll('.icon[data-icon]').forEach(img => {
    img.src = iconUrl(img.dataset.icon, color);
  });
}

function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('Dashboard-theme', theme);
  updateAllIcons();
}

const APP = {
  user: null,
  role: null,

  async init() {
    console.log('[Dashboard App] Initializing...');
    const savedTheme = localStorage.getItem('Dashboard-theme') || 'light';
    applyTheme(savedTheme);

    DashboardAuth.onAuthStateChange((user) => {
      this.user = user;
      this.role = user ? DashboardAuth.getRole() : null;
      this.renderLayout();
      if (user && window.location.hash === '#/login') {
        window.location.hash = '#/financeiro';
      }
    });

    const user = await DashboardAuth.getCurrentUser();
    if (user) {
      this.user = user;
      this.role = DashboardAuth.getRole();
    }

    this.renderLayout();
    router.init(this);
    updateAllIcons();
  },

  renderLayout() {
    const appRoot = document.getElementById('app-root');
    const currentHash = window.location.hash.replace('#', '') || '/login';

    if (!this.user) {
      appRoot.innerHTML = '<div id="app-content"></div>';
      return;
    }

    const isFinanceiro = this.role === 'financeiro' || this.role === 'admin';
    const isVendas = this.role === 'vendas' || this.role === 'admin';
    const isAdmin = this.role === 'admin';

    appRoot.innerHTML = `
      <header class="header">
        <div class="logo">
          <img class="logo-img" src="https://i.ibb.co/TxRDrPN2/logo-Dashboard.png" alt="Dashboard Financeiro BI">
          <div>
            <h1 style="font-size:24px;margin:0">Dashboard Financeiro BI</h1>
            <span style="font-size:14px">Dashboard Financeiro</span>
          </div>
        </div>
        <button class="nav-toggle" id="navToggle" aria-label="Menu">
          <span></span><span></span><span></span>
        </button>
        <div class="controls">
          <nav class="nav-menu">
            ${isFinanceiro ? `<a href="#/financeiro" data-link data-active="${currentHash === '/financeiro'}">Painel Financeiro</a>` : ''}
            ${isVendas ? `<a href="#/vendas" data-link data-active="${currentHash === '/vendas'}">Painel de Vendas</a>` : ''}
            ${isAdmin ? `<a href="#/admin" data-link data-active="${currentHash === '/admin'}">Admin</a>` : ''}
          </nav>
          <button class="btn-pdf" id="btn-pdf" title="Gerar PDF para Apresentacao">
            <img class="icon" data-icon="material-symbols:picture-as-pdf-outline" alt=""
                 style="filter: brightness(0) invert(1);"> PDF
          </button>
          <button class="theme-toggle" id="themeToggle" title="Alternar Tema">
            <img class="icon icon-sun" data-icon="material-symbols:light-mode" alt="">
            <img class="icon icon-moon" data-icon="material-symbols:dark-mode" alt="">
          </button>
          <button id="btn-logout">Sair</button>
        </div>
      </header>
      <div class="mobile-drawer-overlay" id="mobileOverlay"></div>
      <div class="mobile-drawer" id="mobileDrawer">
        <div class="mobile-drawer-header">
          <span style="font-weight:700;font-size:16px">Menu</span>
          <button class="mobile-drawer-close" id="mobileDrawerClose">&times;</button>
        </div>
        <nav class="mobile-nav-menu">
          ${isFinanceiro ? `<a href="#/financeiro" data-link data-active="${currentHash === '/financeiro'}">Painel Financeiro</a>` : ''}
          ${isVendas ? `<a href="#/vendas" data-link data-active="${currentHash === '/vendas'}">Painel de Vendas</a>` : ''}
          ${isAdmin ? `<a href="#/admin" data-link data-active="${currentHash === '/admin'}">Admin</a>` : ''}
        </nav>
        <div class="mobile-drawer-divider"></div>
        <div class="mobile-drawer-actions">
          <button class="btn-pdf" id="mobile-btn-pdf">
            <img class="icon" data-icon="material-symbols:picture-as-pdf-outline" alt=""
                 style="filter: brightness(0) invert(1);"> PDF
          </button>
          <button class="theme-toggle" id="mobileThemeToggle" title="Alternar Tema">
            <img class="icon icon-sun" data-icon="material-symbols:light-mode" alt="">
            <img class="icon icon-moon" data-icon="material-symbols:dark-mode" alt="">
          </button>
          <button id="mobile-btn-logout">Sair</button>
        </div>
      </div>
      <div id="app-content" class="main-content"></div>
      <div class="footer">
        <img class="icon icon-sm" data-icon="material-symbols:database" alt="">
        Dados processados via pipeline Python - Dashboard Financeiro BI 2026<br>Desenvolvido por <strong>Silvano Moraes de Souza</strong> - Especialista em Engenharia de Dados, Programação, Governança de DBA e Cibersegurança Corporativa
      </div>
    `;

    document.getElementById('themeToggle').addEventListener('click', () => {
      const current = document.documentElement.getAttribute('data-theme');
      applyTheme(current === 'light' ? 'dark' : 'light');
      window.dispatchEvent(new CustomEvent('Dashboard:theme-change'));
    });

    document.getElementById('btn-logout').addEventListener('click', () => {
      DashboardAuth.logout();
    });

    const btnPdf = document.getElementById('btn-pdf');
    if (btnPdf) {
      btnPdf.addEventListener('click', () => {
        const originalTheme = document.documentElement.getAttribute('data-theme');
        applyTheme('light');
        setTimeout(() => {
          window.print();
          applyTheme(originalTheme);
        }, 500);
      });
    }

    document.querySelectorAll('.nav-menu a').forEach(link => {
      link.addEventListener('click', () => {
        document.querySelectorAll('.nav-menu a').forEach(a => a.setAttribute('data-active', 'false'));
        link.setAttribute('data-active', 'true');
      });
    });

    updateAllIcons();

    // Mobile drawer
    const navToggle = document.getElementById('navToggle');
    const mobileDrawer = document.getElementById('mobileDrawer');
    const mobileOverlay = document.getElementById('mobileOverlay');
    const mobileDrawerClose = document.getElementById('mobileDrawerClose');
    function openDrawer() { mobileDrawer.classList.add('open'); mobileOverlay.classList.add('open'); }
    function closeDrawer() { mobileDrawer.classList.remove('open'); mobileOverlay.classList.remove('open'); }
    if (navToggle) navToggle.addEventListener('click', openDrawer);
    if (mobileOverlay) mobileOverlay.addEventListener('click', closeDrawer);
    if (mobileDrawerClose) mobileDrawerClose.addEventListener('click', closeDrawer);
    document.querySelectorAll('.mobile-nav-menu a').forEach(link => {
      link.addEventListener('click', () => {
        document.querySelectorAll('.mobile-nav-menu a').forEach(a => a.setAttribute('data-active', 'false'));
        link.setAttribute('data-active', 'true');
        closeDrawer();
      });
    });
    const mobileThemeToggle = document.getElementById('mobileThemeToggle');
    if (mobileThemeToggle) {
      mobileThemeToggle.addEventListener('click', () => {
        const current = document.documentElement.getAttribute('data-theme');
        applyTheme(current === 'light' ? 'dark' : 'light');
        window.dispatchEvent(new CustomEvent('Dashboard:theme-change'));
      });
    }
    const mobileBtnPdf = document.getElementById('mobile-btn-pdf');
    if (mobileBtnPdf) {
      mobileBtnPdf.addEventListener('click', () => {
        const originalTheme = document.documentElement.getAttribute('data-theme');
        applyTheme('light');
        setTimeout(() => { window.print(); applyTheme(originalTheme); }, 500);
      });
    }
    const mobileBtnLogout = document.getElementById('mobile-btn-logout');
    if (mobileBtnLogout) mobileBtnLogout.addEventListener('click', () => DashboardAuth.logout());
  },

  getContentContainer() {
    return document.getElementById('app-content');
  }
};

window.addEventListener('DOMContentLoaded', () => {
  APP.init().catch(err => {
    console.error('[Dashboard App] Fatal init error:', err);
    const root = document.getElementById('app-root');
    if (root) {
      root.innerHTML = `
        <div style="display:flex;align-items:center;justify-content:center;min-height:100vh;flex-direction:column;gap:16px;padding:24px;text-align:center">
          <div style="font-size:48px">⚠️</div>
          <h2 style="margin:0">Erro ao carregar aplicação</h2>
          <p style="color:var(--text-secondary);max-width:400px">${err.message || 'Verifique sua conexão de rede e tente novamente.'}</p>
          <button onclick="location.reload()" style="padding:10px 24px;border:none;border-radius:8px;background:#10b981;color:#fff;cursor:pointer;font-size:14px">Recarregar</button>
        </div>`;
    }
  });
});

export { APP, updateAllIcons, applyTheme, getIconColor, iconUrl };

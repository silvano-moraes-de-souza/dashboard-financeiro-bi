//========================================
// router.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================
import { renderLoginPage } from './pages/login.js';
import { renderFinanceiroPage } from './pages/financeiro.js';
import { renderVendasPage } from './pages/vendas.js';
import { renderAdminPage } from './pages/admin.js';
import { DashboardAuth } from './auth.js';

const router = {
  routes: {
    '/login': { view: 'login', requiresAuth: false },
    '/financeiro': { view: 'financeiro', requiresAuth: true, allowedRoles: ['admin', 'financeiro'] },
    '/vendas': { view: 'vendas', requiresAuth: true, allowedRoles: ['admin', 'vendas'] },
    '/admin': { view: 'admin', requiresAuth: true, allowedRoles: ['admin'] },
    '/': { redirect: '/financeiro' }
  },

  async init() {
    window.addEventListener('hashchange', () => this.handleRoute());
    await this.handleRoute();
  },

  navigate(path) {
    window.location.hash = path;
  },

  async handleRoute() {
    const hash = window.location.hash.replace('#', '') || '/';
    const path = hash.split('?')[0];
    const route = this.routes[path] || { redirect: '/login' };

    if (route.redirect) {
      window.location.hash = route.redirect;
      return;
    }

    if (route.requiresAuth) {
      const user = await DashboardAuth.getCurrentUser();
      if (!user) {
        window.location.hash = '/login';
        return;
      }
      if (route.allowedRoles && !route.allowedRoles.some(r => r === DashboardAuth.getRole())) {
        window.location.hash = '/login';
        return;
      }
    }

    this.render(route.view);
  },

  render(viewName) {
    const appContent = document.getElementById('app-content') || document.getElementById('app-root');
    appContent.innerHTML = '<div class="loading-spinner" style="margin-top:40px">Carregando...</div>';

    switch (viewName) {
      case 'login':
        renderLoginPage(appContent);
        break;
      case 'financeiro':
        renderFinanceiroPage(appContent);
        break;
      case 'vendas':
        renderVendasPage(appContent);
        break;
      case 'admin':
        renderAdminPage(appContent);
        break;
      default:
        appContent.innerHTML = '<p>404: Pagina nao encontrada.</p>';
    }
  }
};

export { router };

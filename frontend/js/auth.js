//========================================
// auth.js - Autenticação local
//========================================

const ALLOWED_DOMAIN = '@Dashboardgreen.eco.br';

function mockUser(email) {
  return {
    id: '00000000-0000-0000-0000-000000000000',
    email: email || 'email@exemplo.com',
    user_metadata: { role: 'admin' },
    app_metadata: { role: 'admin' },
  };
}

class AuthManager {
    constructor() {
        this.user = null;
        this.role = null;
        this.listeners = [];
    }

    async getCurrentUser() {
        const saved = localStorage.getItem('APP_local_user');
        if (saved) {
            this.user = JSON.parse(saved);
            this.role = this.user.user_metadata?.role || 'admin';
            return this.user;
        }
        return null;
    }

    async login(email, password) {
        this.user = mockUser(email);
        this.role = 'admin';
        localStorage.setItem('APP_local_user', JSON.stringify(this.user));
        this.listeners.forEach(cb => cb(this.user));
        return { user: this.user };
    }

    async loginWithGoogle() {
        throw new Error('Login com Google disponivel apenas em ambiente local');
    }

    async logout() {
        localStorage.removeItem('APP_local_user');
        this.user = null;
        this.role = null;
        window.location.replace('/');
    }

    onAuthStateChange(callback) {
        this.listeners.push(callback);
    }

    getRole() { return this.role; }
    isAdmin() { return this.role === 'admin'; }
    isFinanceiro() { return this.role === 'financeiro' || this.isAdmin(); }
    isVendas() { return this.role === 'vendas' || this.isAdmin(); }

    hasAccess(view) {
        if (this.isAdmin()) return true;
        if (view === 'financeiro') return this.isFinanceiro();
        if (view === 'vendas') return this.isVendas();
        if (view === 'admin') return this.isAdmin();
        return false;
    }
}

export const DashboardAuth = new AuthManager();

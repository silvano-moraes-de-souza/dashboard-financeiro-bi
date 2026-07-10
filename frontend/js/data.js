//========================================
// data.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================

export const dataService = {
  cache: {},
  _cacheTTL: 5 * 60 * 1000,

  _getApiBase() {
    return window.location.origin;
  },

  _isCacheValid(key) {
    const entry = this.cache[key];
    return entry && (Date.now() - entry.ts < this._cacheTTL);
  },

  _setCache(key, data) {
    this.cache[key] = { data, ts: Date.now() };
  },

  _getCache(key) {
    if (this._isCacheValid(key)) return this.cache[key].data;
    return null;
  },

  clearCache() { this.cache = {}; },

  async fetchAllData(params) {
    const qs = params ? '?' + params.toString() : '';
    const cacheKey = `all:${qs}`;
    const cached = this._getCache(cacheKey);
    if (cached) return cached;

    let data = null;
    try {
      const resp = await fetch(`${this._getApiBase()}/api/dados${qs}`);
      if (resp.ok) {
        data = await resp.json();
      }
    } catch (e) {
      console.error('[DataService] Flask /api/dados falhou:', e.message);
    }

    if (data) {
      data.kpis = data.kpis || {};
      data.evolucao_mensal = data.evolucao_mensal || { labels: [], data: [], data_anterior: [], ano_atual: new Date().getFullYear() };
      data.evolucao_diaria = data.evolucao_diaria || { labels: [], data: [] };
      data.rank_semana = data.rank_semana || { labels: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'], data: new Array(7).fill(0) };
      data.top10 = data.top10 || { labels: [], data: [] };
      data.market_share = data.market_share || { labels: [], data: [] };
      data.rank_categoria = data.rank_categoria || { labels: [], data: [] };
      data.vendas_uf = data.vendas_uf || { labels: [], data: [] };
      data.pm = data.pm || { ponderado: 0, por_empresa: {} };
      data.transacoes_recentes = data.transacoes_recentes || [];
      data.top20_clientes = data.top20_clientes || [];
      data.mix_por_cliente = data.mix_por_cliente || {};
      data.todos_produtos = data.todos_produtos || [];
      data.filtros = data.filtros || { anos: [], clientes: [], produtos: [], empresas: [] };
      this._setCache(cacheKey, data);
    }

    return data;
  },

  async fetchMapData(params) {
    const qs = params ? '?' + params.toString() : '';
    const cacheKey = `mapa:${qs}`;
    const cached = this._getCache(cacheKey);
    if (cached) return cached;

    let data = null;
    try {
      const resp = await fetch(`${this._getApiBase()}/api/mapa${qs}`);
      if (resp.ok) {
        const raw = await resp.json();
        const dadosPorUf = {};
        let maxVal = 0;
        const ufData = raw.dados_por_uf || {};
        Object.keys(ufData).forEach(uf => {
          const item = ufData[uf];
          dadosPorUf[uf] = {
            nome: item.nome || uf,
            valor: item.valor || 0,
            notas: item.notas || 0,
            porcentagem: String(item.porcentagem || '0.0'),
          };
          if ((item.valor || 0) > maxVal) maxVal = item.valor;
        });
        data = {
          dados_por_uf: dadosPorUf,
          max_valor: maxVal,
          total_geral: raw.total_geral || 0,
          total_estados: raw.total_estados || 0,
        };
      }
    } catch (e) {
      console.error('[DataService] Flask /api/mapa falhou:', e.message);
    }

    if (data) {
      this._setCache(cacheKey, data);
    }
    return data;
  },

  async fetchVendasData(params) {
    const qs = params ? '?' + params.toString() : '';
    const cacheKey = `vendas:${qs}`;
    const cached = this._getCache(cacheKey);
    if (cached) return cached;

    let data = null;
    try {
      const resp = await fetch(`${this._getApiBase()}/api/vendas${qs}`);
      if (resp.ok) {
        data = await resp.json();
      }
    } catch (e) {
      console.error('[DataService] Flask /api/vendas falhou:', e.message);
    }

    if (data) {
      data.kpis = data.kpis || {};
      data.evolucao_mensal = data.evolucao_mensal || { labels: [], data: [], data_anterior: [], ano_atual: new Date().getFullYear() };
      data.evolucao_diaria = data.evolucao_diaria || { labels: [], data: [] };
      data.rank_semana = data.rank_semana || { labels: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab'], data: new Array(7).fill(0) };
      data.top10 = data.top10 || { labels: [], data: [] };
      data.market_share = data.market_share || { labels: [], data: [] };
      data.rank_categoria = data.rank_categoria || { labels: [], data: [] };
      data.vendas_uf = data.vendas_uf || { labels: [], data: [] };
      data.volume = data.volume || { por_empresa: {} };
      data.transacoes_recentes = data.transacoes_recentes || [];
      data.top20_clientes = data.top20_clientes || [];
      data.mix_por_cliente = data.mix_por_cliente || {};
      data.todos_produtos = data.todos_produtos || [];
      data.filtros = data.filtros || { anos: [], clientes: [], produtos: [], empresas: [] };
      data.mapa_caixas = data.mapa_caixas || { dados_por_uf: {}, max_valor: 0 };
      this._setCache(cacheKey, data);
    }

    return data;
  },

  async fetchUsuarios() {
    return [{ id: 'local', email: 'email@exemplo.com', nome: 'Desenvolvimento', role: 'admin' }];
  }
};

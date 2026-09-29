//========================================
// financeiro.js
// Descrição:
// Criado por: Silvano Moraes de Souza
//========================================
import { dataService } from '../data.js';
import { updateAllIcons, applyTheme } from '../app.js';

const ICONIFY_BASE = 'https://api.iconify.design';

function getIconColor() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? '34D399' : '10B981';
}

function iconUrl(name, color) {
  return `${ICONIFY_BASE}/${name}.svg?color=%23${color}`;
}

function getTextColor() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? '#f0f0fa' : '#1a1b1f';
}

function getGridColor() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? '#2d2d44' : '#e2e8f0';
}

const fmtMoney = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const fmtNum = new Intl.NumberFormat('pt-BR');
const MESES_PT = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

let DASHBOARD_DATA = null;
let MAPA_DATA = null;
let GEOJSON_CACHE = null;
let CLICK_FILTERS = { uf: null, categoria: null, dia: null, dia_semana: null };
let charts = {};
let _financeiroThemeHandler = null;

const ESTADO_UF_MAP = {
    'Acre': 'AC', 'Alagoas': 'AL', 'Amapa': 'AP', 'Amazonas': 'AM',
    'Bahia': 'BA', 'Ceara': 'CE', 'Distrito Federal': 'DF', 'Espirito Santo': 'ES',
    'Goias': 'GO', 'Maranhao': 'MA', 'Mato Grosso': 'MT', 'Mato Grosso do Sul': 'MS',
    'Minas Gerais': 'MG', 'Para': 'PA', 'Paraiba': 'PB', 'Parana': 'PR',
    'Pernambuco': 'PE', 'Piaui': 'PI', 'Rio de Janeiro': 'RJ', 'Rio Grande do Norte': 'RN',
    'Rio Grande do Sul': 'RS', 'Rondonia': 'RO', 'Roraima': 'RR', 'Santa Catarina': 'SC',
    'Sao Paulo': 'SP', 'Sergipe': 'SE', 'Tocantins': 'TO',
    'Amapá': 'AP', 'Ceará': 'CE', 'Espírito Santo': 'ES', 'Goiás': 'GO',
    'Maranhão': 'MA', 'Pará': 'PA', 'Paraíba': 'PB', 'Paraná': 'PR',
    'Piauí': 'PI', 'Rondônia': 'RO', 'São Paulo': 'SP'
};

function getPageHTML() {
  return `
    <div class="container">
      <div id="financeiro-filters" style="margin-bottom:20px"></div>
      <div id="kpi-financeiro" class="kpi-cards"></div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:show-chart" alt=""> Evolucao Mensal de Receita</h3>
  <div class="chart-container"><canvas id="evolucaoChart"></canvas></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:pie-chart" alt=""> Participacao de Mercado: FILIAL_B vs FILIAL</h3>
  <div class="chart-container"><canvas id="marketShareChart"></canvas></div>
  </div>
  </div>

  <div class="grid-2" style="margin-bottom:20px">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:groups" alt=""> Top 30 Clientes por Faturamento</h3>
  <div id="top20ClientesList" class="top20-list"></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:inventory-2" alt=""> Mix de Produtos <span id="mixClienteName" style="color:#10b981;font-size:13px"></span></h3>
  <div id="mixClienteBody" class="mix-body">
  <div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Clique em um cliente ao lado para ver seu mix</span></div>
  </div>
  </div>
  </div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:category" alt=""> Faturamento por Categoria</h3>
  <div class="chart-container"><canvas id="rankCategoriaChart"></canvas></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:leaderboard" alt=""> Top 10 Produtos</h3>
  <div class="chart-container"><canvas id="top10Chart"></canvas></div>
  </div>
  </div>

  <div class="grid-2" style="margin-bottom:20px">
  <div class="card map-container">
  <h3><img class="icon section-icon" data-icon="material-symbols:map" alt=""> Mapa de Vendas por Estado</h3>
  <div style="display:flex;gap:16px;align-items:stretch">
  <div style="flex:1;position:relative;min-width:0">
  <div id="mapaBrasil" style="position:relative;width:100%;height:380px;"></div>
  <div class="map-legend">
  <span>Menor</span>
  <div class="map-legend-bar" id="mapLegendBar"></div>
  <span>Maior</span>
  </div>
  </div>
  <div class="map-info-card" id="mapInfoCard">
  <div class="map-info-card-header" id="mapInfoCardHeader">Passe o mouse sobre um estado</div>
  <div class="map-info-card-body" id="mapInfoCardBody">
  <div class="map-info-placeholder"><img class="icon" data-icon="material-symbols:mouse" alt="" style="width:28px;height:28px;opacity:.4"> <span style="color:var(--text-secondary);font-size:13px">Explore o mapa para ver os dados detalhados</span></div>
  </div>
  </div>
  </div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:leaderboard" alt=""> Ranking por Estado</h3>
  <div id="mapRank" class="map-rank"></div>
  </div>
  </div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:calendar-today" alt=""> Evolucao Diaria de Receita</h3>
  <div class="chart-container"><canvas id="evolucaoDiariaChart"></canvas></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:event-repeat" alt=""> Rank: Melhor Dia da Semana</h3>
  <div class="chart-container"><canvas id="rankSemanaChart"></canvas></div>
  </div>
  </div>

  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:scatter-plot" alt=""> Matriz de Rentabilidade</h3>
  <div style="display:flex;flex-wrap:wrap;gap:16px;margin-bottom:16px">
    <div style="flex:1;min-width:280px;height:320px">
      <div class="chart-container" style="height:100%"><canvas id="rentabilidadeChart"></canvas></div>
    </div>
    <div style="flex:0 0 190px;font-size:12px;color:var(--text-secondary);padding-top:8px">
      <div style="margin-bottom:8px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;font-size:11px">Quadrantes</div>
      <div style="margin-bottom:4px"><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#10b981;margin-right:6px"></span>Cliente Ideal</div>
      <div style="margin-bottom:4px"><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#f59e0b;margin-right:6px"></span>Potencial Expansão</div>
      <div style="margin-bottom:4px"><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#38bdf8;margin-right:6px"></span>Baixo Impacto</div>
      <div style="margin-bottom:4px"><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:#ef4444;margin-right:6px"></span>Risco de Margem</div>
      <div style="margin-top:12px;border-top:1px solid var(--border);padding-top:10px">
        <div style="font-weight:700;text-transform:uppercase;letter-spacing:.5px;font-size:11px;margin-bottom:4px">Insights</div>
        <div id="rentabilidadeInsights"></div>
      </div>
    </div>
  </div>
  <div id="margemMensalCard" style="margin-bottom:16px;display:none">
    <h3 style="font-size:13px;margin-bottom:8px"><img class="icon section-icon" data-icon="material-symbols:bar-chart" alt=""> <span id="margemMensalTitle">Margem % Mensal: Todos os Clientes</span></h3>
    <div class="chart-container" style="height:180px"><canvas id="margemMensalChart"></canvas></div>
  </div>
  <div class="table-wrapper">
    <table id="rentabilidadeTable">
      <thead id="rentabilidadeHead">
        <tr>
          <th data-col="cliente" style="cursor:pointer">Cliente</th>
          <th data-col="receita" style="cursor:pointer">Receita</th>
          <th data-col="lucro" style="cursor:pointer">Lucro</th>
          <th data-col="margem" style="cursor:pointer">Margem%</th>
          <th data-col="pedidos" style="cursor:pointer">Pedidos</th>
          <th data-col="ticket_medio" style="cursor:pointer">Ticket Médio</th>
          <th data-col="status" style="cursor:pointer">Status</th>
        </tr>
      </thead>
      <tbody id="rentabilidadeBody"></tbody>
    </table>
  </div>
  </div>
    </div>
  `;
}

export async function renderFinanceiroPage(appRoot) {
  try {
    const paramsIniciais = new URLSearchParams();
    paramsIniciais.set('ano', String(new Date().getFullYear()));
    DASHBOARD_DATA = await dataService.fetchAllData(paramsIniciais);
    if (!DASHBOARD_DATA) {
      throw new Error('Nao foi possivel carregar os dados. Verifique a conexao com Supabase ou a API.');
    }
    appRoot.innerHTML = getPageHTML();
    renderFilters();
    renderKPIs();
    requestAnimationFrame(() => {
      renderCharts();
      requestAnimationFrame(() => {
        renderTop20Clientes();
        renderRentabilidade();
        loadMap(paramsIniciais);
        updateAllIcons();
      });
    });
  } catch (err) {
    console.error('[Financeiro] Erro ao carregar dados:', err);
    appRoot.innerHTML = `<div class="card"><h3>Erro ao carregar dados</h3><p style="color:var(--text-secondary)">${err.message}</p></div>`;
  }

  if (_financeiroThemeHandler) window.removeEventListener('Dashboard:theme-change', _financeiroThemeHandler);
  _financeiroThemeHandler = onThemeChange;
  window.addEventListener('Dashboard:theme-change', _financeiroThemeHandler);
}

function onThemeChange() {
  if (DASHBOARD_DATA) {
    setTimeout(() => {
      renderCharts();
      renderRentabilidade();
      if (MAPA_DATA) desenharMapa();
    }, 100);
  }
}

function renderFilters() {
  const f = DASHBOARD_DATA.filtros || {};
  const mesesPt = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

  const container = document.getElementById('financeiro-filters');
  if (!container) return;

  container.innerHTML = `
    <div class="controls" style="flex-wrap:wrap;gap:10px;justify-content:flex-start">
      <select class="filter-empresa" id="filterEmpresa">
        <option value="TODAS">Todas as Empresas</option>
        ${(f.empresas || ['FILIAL_B', 'FILIAL']).map(e => `<option value="${e}">${e}</option>`).join('')}
      </select>
<select class="filter-empresa" id="filterNatureza" style="min-width:110px">
      <option value="Venda" selected>Venda</option>
      <option value="TODOS">Todas Naturezas</option>
    </select>
    <select class="filter-empresa" id="filterTipoPessoa" style="min-width:110px">
      <option value="TODOS">CPF/CNPJ</option>
      <option value="Física">CPF</option>
      <option value="Jurídica">CNPJ</option>
    </select>
      <select class="filter-empresa" id="filterAno" style="min-width:80px">
        <option value="TODOS">Todos Anos</option>
        ${(f.anos || []).map(a => `<option value="${a}"${a == new Date().getFullYear() ? ' selected' : ''}>${a}</option>`).join('')}
      </select>
      <select class="filter-empresa" id="filterMes" style="min-width:100px">
        <option value="TODOS">Todos Meses</option>
        ${Array.from({length:12}, (_, i) => `<option value="${i+1}">${mesesPt[i+1]}</option>`).join('')}
      </select>
      <select class="filter-empresa" id="filterProduto" style="min-width:140px">
        <option value="TODOS">Todos Produtos</option>
        ${(f.produtos || []).map(p => `<option value="${p}">${p.length > 40 ? p.slice(0,38) + '...' : p}</option>`).join('')}
      </select>
      <div class="multiselect-container" id="clienteContainer">
        <div class="multiselect-trigger" id="clienteTrigger">
          <img class="icon multiselect-trigger-icon" data-icon="material-symbols:search" alt="">
          <span class="multiselect-label" id="clienteLabel">Todos Clientes</span>
          <img class="icon multiselect-arrow" data-icon="material-symbols:arrow-drop-down-rounded" alt="">
        </div>
        <div class="multiselect-dropdown" id="clienteDropdown">
          <input type="text" class="multiselect-search" id="clienteSearchInput" placeholder="Buscar cliente...">
          <label class="multiselect-option select-all">
            <input type="checkbox" id="clienteSelectAll" checked> Selecionar Todos
          </label>
          <div class="multiselect-options" id="clienteOptions"></div>
        </div>
      </div>
    </div>
  `;

  const optionsDiv = document.getElementById('clienteOptions');
  (f.clientes || []).forEach(c => {
    const label = document.createElement('label');
    label.className = 'multiselect-option';
    label.dataset.cliente = c;
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = true; cb.value = c;
    label.appendChild(cb);
    label.appendChild(document.createTextNode(' ' + c));
    optionsDiv.appendChild(label);
  });

  ['filterEmpresa', 'filterNatureza', 'filterTipoPessoa', 'filterAno', 'filterMes', 'filterProduto'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('change', () => aplicarFiltros());
  });

  const trigger = document.getElementById('clienteTrigger');
  const dropdown = document.getElementById('clienteDropdown');
  const searchInput = document.getElementById('clienteSearchInput');
  const selectAll = document.getElementById('clienteSelectAll');
  const optionsContainer = document.getElementById('clienteOptions');

  trigger.addEventListener('click', (e) => {
    e.stopPropagation();
    dropdown.classList.toggle('open');
    if (dropdown.classList.contains('open')) {
      searchInput.value = ''; searchInput.focus();
      filterClientOptions('');
    }
  });

  searchInput.addEventListener('input', () => filterClientOptions(searchInput.value));

  selectAll.addEventListener('change', () => {
    const checked = selectAll.checked;
    optionsContainer.querySelectorAll('.multiselect-option:not(.select-all)').forEach(opt => {
      opt.querySelector('input[type="checkbox"]').checked = checked;
    });
    updateClienteLabel();
    aplicarFiltros();
  });

  optionsContainer.addEventListener('change', (e) => {
    if (e.target.type === 'checkbox') {
      updateSelectAll();
      updateClienteLabel();
      aplicarFiltros();
    }
  });

  document.addEventListener('click', (e) => {
    const cc = document.getElementById('clienteContainer');
    if (cc && !cc.contains(e.target)) dropdown.classList.remove('open');
  });

  function filterClientOptions(query) {
    optionsContainer.querySelectorAll('.multiselect-option:not(.select-all)').forEach(opt => {
      const name = opt.dataset.cliente || opt.textContent.trim();
      opt.style.display = (!query || name.toLowerCase().includes(query.toLowerCase())) ? '' : 'none';
    });
  }

  function updateSelectAll() {
    const options = optionsContainer.querySelectorAll('.multiselect-option:not(.select-all)');
    selectAll.checked = options.length > 0 && Array.from(options).every(opt => opt.querySelector('input[type="checkbox"]').checked);
  }

  function updateClienteLabel() {
    const options = optionsContainer.querySelectorAll('.multiselect-option:not(.select-all)');
    const checked = Array.from(options).filter(opt => opt.querySelector('input[type="checkbox"]').checked);
    const label = document.getElementById('clienteLabel');
    if (checked.length === options.length) label.textContent = 'Todos Clientes';
    else if (checked.length === 0) label.textContent = 'Nenhum Cliente';
    else if (checked.length === 1) { const name = checked[0].querySelector('input[type="checkbox"]').value; label.textContent = name.length > 22 ? name.slice(0,20) + '...' : name; }
    else label.textContent = checked.length + ' clientes';
  }
}

function renderKPIs() {
  const k = DASHBOARD_DATA.kpis;
  const pm = DASHBOARD_DATA.pm || {};
  const container = document.getElementById('kpi-financeiro');
  if (!container || !k) return;

  container.innerHTML = `
    <div class="kpi-card faturamento">
      <div class="kpi-header"><span class="label">Faturamento Total</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:attach-money" alt=""></div></div>
      <span class="value">${fmtMoney.format(k.faturamento || 0)}</span>
      <span class="trend">Total Liquido</span>
    </div>
    <div class="kpi-card custos">
      <div class="kpi-header"><span class="label">Custos Estimados</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:receipt" alt=""></div></div>
      <span class="value">${fmtMoney.format(k.custo_total || 0)}</span>
      <span class="trend">Custo Total: ${k.custo_percentual || 0}%</span>
    </div>
    <div class="kpi-card ticket">
      <div class="kpi-header"><span class="label">Ticket Medio</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:shopping-bag-outline" alt=""></div></div>
      <span class="value">${fmtMoney.format(k.ticket_medio || 0)}</span>
      <span class="trend">Media / CX / 12</span>
    </div>
    <div class="kpi-card notas">
      <div class="kpi-header"><span class="label">TOTAL DE NOTAS E CX</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:description-outline" alt=""></div></div>
      <span class="value">${k.total_notas || 0} / ${k.total_caixas || 0}</span>
      <span class="trend">NOTAS/CX</span>
    </div>
    <div class="kpi-card pm">
      <div class="kpi-header"><span class="label">PM Ponderado</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:analytics" alt=""></div></div>
      <span class="value">${fmtMoney.format(pm.ponderado || k.ticket_medio || 0)}</span>
      <span class="trend" id="kpiPMTrend">${renderPMbyEmpresa(pm)}</span>
    </div>
  `;
  updateAllIcons();
}

function renderPMbyEmpresa(pm) {
  const empresas = Object.keys(pm.por_empresa || {});
  if (empresas.length === 0) return 'Ultimos 12 meses';
  return empresas.map(e => {
    const v = pm.por_empresa[e];
    return `${e}: ${fmtMoney.format(v.preco_medio)} (${(v.share_12m || 0).toFixed(1)}%)`;
  }).join('<br>');
}

function renderCharts(dataOverride) {
  const DDATA = dataOverride || DASHBOARD_DATA;
  if (!DDATA) return;
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

  const palette = isDark
    ? ['#38BDF8', '#34D399', '#FB923C', '#A78BFA', '#F87171', '#818CF8', '#2DD4BF']
    : ['#3B82F6', '#10B981', '#F59E0B', '#8B5CF6', '#EF4444', '#6366F1', '#14B8A6'];

  Chart.register(ChartDataLabels);
  Chart.defaults.set('plugins.datalabels', { display: false });

  Chart.defaults.color = getTextColor();
  Chart.defaults.borderColor = getGridColor();
  Chart.defaults.font.family = 'Inter, Segoe UI, sans-serif';

  const getBarColor = (label, dimension, defaultColor) => {
    const el = document.getElementById(`filter${dimension}`);
    const clickVal = CLICK_FILTERS[dimension.toLowerCase()];
    const activeVal = el ? el.value : clickVal;
    if (!activeVal || activeVal === 'TODOS' || activeVal === 'TODAS' || activeVal === '') return defaultColor;
    if (label.toString() === activeVal.toString()) return defaultColor;
    return isDark ? '#334155' : '#E2E8F0';
  };

  const commonY = (v) => 'R$ ' + (v / 1000).toFixed(0) + 'k';
  const destroy = (name) => { if (charts[name]) { charts[name].destroy(); charts[name] = null; } };

  // 1. Evolucao Mensal
  destroy('evolucao');
  let anoAtual = DDATA.evolucao_mensal.ano_atual || new Date().getFullYear();
  let evolData = DDATA.evolucao_mensal.data || [];
  let evolDataAnterior = DDATA.evolucao_mensal.data_anterior || [];
  let evolLabels = MESES_PT;

  if (document.getElementById('evolucaoChart')) {
    charts.evolucao = new Chart(document.getElementById('evolucaoChart').getContext('2d'), {
      type: 'line',
      data: {
        labels: evolLabels,
        datasets: [{
          label: 'Total',
          data: evolData.map((v, i) => (v || 0) + (evolDataAnterior[i] || 0)),
          borderColor: palette[2], backgroundColor: palette[2],
          pointRadius: 4, pointHoverRadius: 6, pointStyle: 'rect',
          fill: false, borderWidth: 2, borderDash: [5, 5]
        }, {
          label: `(${anoAtual})`,
          data: evolData,
          borderColor: palette[0], backgroundColor: palette[0],
          borderWidth: 3, fill: false, tension: 0.4,
          pointRadius: (ctx) => ctx.raw > 0 ? 5 : 0,
          pointHoverRadius: 6, pointBackgroundColor: palette[0]
        }, {
          label: `(${anoAtual - 1})`,
          data: evolDataAnterior,
          borderColor: isDark ? '#64748B' : '#9CA3AF',
          backgroundColor: isDark ? '#64748B' : '#9CA3AF',
          borderWidth: 2, borderDash: [6, 6], fill: false, tension: 0.4,
          pointRadius: 3, pointHoverRadius: 5,
          pointBackgroundColor: isDark ? '#64748B' : '#9CA3AF'
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            const label = (idx + 1).toString();
            const el = document.getElementById('filterMes');
            el.value = (el.value === label) ? 'TODOS' : label;
            aplicarFiltros();
          }
        },
        plugins: {
          legend: { labels: { color: getTextColor(), usePointStyle: true, boxWidth: 8 } },
          tooltip: {
            callbacks: {
              label: function(context) {
                const value = context.raw;
                const idx = context.dataIndex;
                const dsIdx = context.datasetIndex;
                if (!value || value === 0) return null;
                const total = (evolData[idx] || 0) + (evolDataAnterior[idx] || 0);
                if (dsIdx === 0) return `Total: ${fmtMoney.format(value)} (100%)`;
                const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                return `${context.dataset.label}: ${fmtMoney.format(value)} (${pct}%)`;
              },
              afterBody: function(items) {
                if (!items.length) return null;
                const idx = items[0].dataIndex;
                const vAtual = evolData[idx] || 0;
                const vAnt = evolDataAnterior[idx] || 0;
                if (vAnt > 0) {
                  const varPct = ((vAtual - vAnt) / vAnt) * 100;
                  const sinal = varPct >= 0 ? '+' : '';
                  const seta = varPct >= 0 ? '\u25B2' : '\u25BC';
                  return `${seta} ${sinal}${Math.abs(varPct).toFixed(1)}% comparado a ${anoAtual - 1}`;
                }
                return null;
              }
            }
          }
        },
        scales: {
          y: { ticks: { callback: commonY, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
          x: { ticks: { color: getTextColor() }, grid: { display: false } }
        }
      }
    });
  }

  // 2. Market Share
  destroy('marketShare');
  if (document.getElementById('marketShareChart')) {
    charts.marketShare = new Chart(document.getElementById('marketShareChart').getContext('2d'), {
      type: 'doughnut',
      data: {
        labels: DDATA.market_share.labels,
        datasets: [{
          data: DDATA.market_share.data,
          backgroundColor: DDATA.market_share.labels.map(l => getBarColor(l, 'Empresa', l === 'FILIAL_B' ? palette[2] : palette[4])),
          borderWidth: isDark ? 2 : 0,
          borderColor: isDark ? '#1E293B' : '#FFFFFF',
          hoverOffset: 12
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, cutout: '75%',
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            const label = DDATA.market_share.labels[idx];
            const el = document.getElementById('filterEmpresa');
            el.value = (el.value === label) ? 'TODAS' : label;
            aplicarFiltros();
          }
        },
        plugins: {
          legend: { position: 'bottom', labels: { color: getTextColor(), padding: 25, usePointStyle: true, boxWidth: 8 } },
          tooltip: {
            callbacks: {
              label: function(context) {
                const value = context.raw;
                const total = context.dataset.data.reduce((a, b) => a + (b || 0), 0);
                const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                return `${context.label}: ${fmtMoney.format(value)} (${pct}%)`;
              }
            }
          }
        }
      }
    });
  }

  // 3. Top 10 Produtos
  destroy('top10');
  if (document.getElementById('top10Chart')) {
    charts.top10 = new Chart(document.getElementById('top10Chart').getContext('2d'), {
      type: 'bar',
      data: {
        labels: DDATA.top10.labels,
        datasets: [{
          label: 'Faturamento', data: DDATA.top10.data,
          backgroundColor: DDATA.top10.labels.map(l => getBarColor(l, 'Produto', palette[1])),
          borderRadius: 4, barPercentage: 0.6
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, indexAxis: 'y',
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            const label = DDATA.top10.labels[idx];
            const el = document.getElementById('filterProduto');
            el.value = (el.value === label) ? 'TODOS' : label;
            aplicarFiltros();
          }
        },
      plugins: {
        legend: { display: false },
        datalabels: { display: true,
          align: 'end', anchor: 'end',
          color: getTextColor(),
          font: { weight: '600', size: 11 },
          formatter: function(value) {
            const total = DDATA.top10.data.reduce((a, b) => a + (b || 0), 0);
            const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
            return pct + '%';
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const value = context.raw;
              const total = context.dataset.data.reduce((a, b) => a + (b || 0), 0);
              const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
              return `${context.label}: ${fmtMoney.format(value)} (${pct}%)`;
            }
          }
        }
      },
      scales: {
        x: { ticks: { callback: commonY, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
        y: { ticks: { color: getTextColor() }, grid: { display: false } }
      }
    }
  });
}

// 4. Evolucao Diaria
  destroy('evolDiaria');
  const dData = DDATA.evolucao_diaria;
  if (document.getElementById('evolucaoDiariaChart')) {
    charts.evolDiaria = new Chart(document.getElementById('evolucaoDiariaChart').getContext('2d'), {
      type: 'bar',
      data: {
        labels: dData.labels,
        datasets: [{
          label: 'Receita diaria', data: dData.data,
          backgroundColor: dData.labels.map(l => getBarColor(l.replace('D', ''), 'Dia', isDark ? 'rgba(52, 211, 153, 0.6)' : 'rgba(16, 185, 129, 0.6)')),
          borderRadius: 2, barPercentage: 0.8
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            const label = dData.labels[idx].replace('D', '');
            CLICK_FILTERS.dia = (CLICK_FILTERS.dia === label) ? null : label;
            aplicarFiltros();
          }
        },
      plugins: {
        legend: { display: false },
        datalabels: { display: true,
          align: 'end', anchor: 'end',
          color: getTextColor(),
          font: { weight: '600', size: 9 },
          formatter: function(value) {
            const total = dData.data.reduce((a, b) => a + (b || 0), 0);
            const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
            return pct > 0 ? pct + '%' : '';
          }
        },
        tooltip: {
          backgroundColor: isDark ? '#1E293B' : '#FFFFFF',
          titleColor: getTextColor(), bodyColor: getTextColor(),
          borderColor: getGridColor(), borderWidth: 1,
          callbacks: {
            title: (items) => `Dia ${items[0].label.replace('D', '')}`,
            label: function(context) {
              const value = context.raw;
              const total = context.dataset.data.reduce((a, b) => a + (b || 0), 0);
              const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
              return `Valor: ${fmtMoney.format(value)} (${pct}%)`;
            }
          }
        }
      },
        scales: {
          y: { ticks: { callback: commonY, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
          x: { ticks: { color: getTextColor(), font: { size: 9 } }, grid: { display: false } }
        }
      }
    });
  }

  // 5. Rank Dia da Semana
  destroy('rankSemana');
  const rsData = DDATA.rank_semana;
  if (document.getElementById('rankSemanaChart')) {
    charts.rankSemana = new Chart(document.getElementById('rankSemanaChart').getContext('2d'), {
      type: 'bar',
      data: {
        labels: rsData.labels,
        datasets: [{
          label: 'Vendas', data: rsData.data,
          backgroundColor: rsData.labels.map((l, i) => getBarColor(i.toString(), 'Dia_semana', palette[i % palette.length])),
          borderRadius: 6, barPercentage: 0.7
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            CLICK_FILTERS.dia_semana = (CLICK_FILTERS.dia_semana === idx.toString()) ? null : idx.toString();
            aplicarFiltros();
          }
        },
      plugins: {
        legend: { display: false },
        datalabels: { display: true,
          align: 'end', anchor: 'end',
          color: getTextColor(),
          font: { weight: '600', size: 11 },
          formatter: function(value) {
            const total = rsData.data.reduce((a, b) => a + (b || 0), 0);
            const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
            return pct + '%';
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const value = context.raw;
              const total = context.dataset.data.reduce((a, b) => a + (b || 0), 0);
              const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
              return `${context.label}: ${fmtMoney.format(value)} (${pct}%)`;
            }
          }
        }
      },
      scales: {
        y: { max: Math.ceil(Math.max(...rsData.data) * 1.2 / 1000) * 1000, ticks: { callback: commonY, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
        x: { ticks: { color: getTextColor() }, grid: { display: false } }
      }
      }
    });
  }

  // 6. Rank de Categoria
  destroy('rankCategoria');
  const rcData = DDATA.rank_categoria;
  if (rcData && rcData.labels && rcData.labels.length > 0 && document.getElementById('rankCategoriaChart')) {
    charts.rankCategoria = new Chart(document.getElementById('rankCategoriaChart').getContext('2d'), {
      type: 'bar',
      data: {
        labels: rcData.labels,
        datasets: [{
          label: 'Faturamento', data: rcData.data,
          backgroundColor: rcData.labels.map(l => getBarColor(l, 'Categoria', palette[3])),
          borderRadius: 4, barPercentage: 0.6
        }]
      },
      options: {
        responsive: true, maintainAspectRatio: false, indexAxis: 'y',
        onClick: (evt, elements) => {
          if (elements.length > 0) {
            const idx = elements[0].index;
            const label = rcData.labels[idx];
            CLICK_FILTERS.categoria = (CLICK_FILTERS.categoria === label) ? null : label;
            aplicarFiltros();
          }
        },
      plugins: {
        legend: { display: false },
        datalabels: { display: true,
          align: 'end', anchor: 'end',
          color: getTextColor(),
          font: { weight: '600', size: 11 },
          formatter: function(value) {
            const total = rcData.data.reduce((a, b) => a + (b || 0), 0);
            const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
            return pct + '%';
          }
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const value = context.raw;
              const total = context.dataset.data.reduce((a, b) => a + (b || 0), 0);
              const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
              return `${context.label}: ${fmtMoney.format(value)} (${pct}%)`;
            }
          }
        }
      },
      scales: {
        x: { ticks: { callback: commonY, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
        y: { ticks: { color: getTextColor() }, grid: { display: false } }
      }
    }
  });
}
}

let selectedRentabilidadeCliente = null;
let rentabilidadeSort = { col: 'receita', dir: 'desc' };

function sortRentabilidade(col) {
  if (rentabilidadeSort.col === col) {
    rentabilidadeSort.dir = rentabilidadeSort.dir === 'asc' ? 'desc' : 'asc';
  } else {
    rentabilidadeSort.col = col;
    rentabilidadeSort.dir = col === 'cliente' ? 'asc' : 'desc';
  }
  renderRentabilidade();
}

function renderRentabilidade() {
  const rentData = DASHBOARD_DATA?.rentabilidade;
  if (!rentData || !rentData.clientes || !rentData.clientes.length) return;

  const medReceita = rentData.mediana_receita;
  const medMargem = rentData.mediana_margem;
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const textColor = getTextColor();
  const gridColor = getGridColor();

  const quadLabels = ['Potencial de Expansao', 'Cliente Ideal', 'Baixo Impacto', 'Risco de Margem'];
  const quadColors = ['#facc15', '#22c55e', '#38bdf8', '#ef4444'];
  const maxReceita = rentData.clientes.length > 0 ? rentData.clientes[0].receita : 1;

  const canvas = document.getElementById('rentabilidadeChart');
  if (!canvas) return;
  if (charts.rentabilidade) charts.rentabilidade.destroy();

  const datasets = [1, 2, 3, 4].map(q => {
    const clientes = rentData.clientes.filter(c => c.quadrante === q);
    return {
      label: quadLabels[q - 1],
      data: clientes.map(c => ({
        x: c.receita,
        y: c.margem,
        r: c.cliente === selectedRentabilidadeCliente ? 18 : Math.max(6, Math.min(22, (c.receita / maxReceita) * 18)),
        cliente: c.cliente,
      })),
      backgroundColor: clientes.map(c => c.cliente === selectedRentabilidadeCliente ? quadColors[q - 1] : quadColors[q - 1] + '99'),
      borderColor: clientes.map(c => c.cliente === selectedRentabilidadeCliente ? '#fff' : quadColors[q - 1]),
      borderWidth: clientes.map(c => c.cliente === selectedRentabilidadeCliente ? 3 : 1),
    };
  });

  charts.rentabilidade = new Chart(canvas.getContext('2d'), {
    type: 'bubble',
    data: { datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      onClick: (evt, elements) => {
        if (elements.length > 0) {
          const raw = charts.rentabilidade.data.datasets[elements[0].datasetIndex].data[elements[0].index];
          selectedRentabilidadeCliente = raw.cliente;
          setTimeout(() => renderRentabilidade(), 50);
        }
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: function(ctx) {
              const d = ctx.raw;
              const full = rentData.clientes.find(c => c.cliente === d.cliente);
              if (!full) return d.cliente;
              return `${d.cliente}: Receita ${fmtMoney.format(full.receita)} | Margem ${full.margem}% | Lucro ${fmtMoney.format(full.lucro)}`;
            }
          }
        }
      },
      scales: {
        x: {
          title: { display: true, text: 'Receita (R$)', color: textColor },
          min: 0,
          max: Math.max(medReceita * 2, 500),
          ticks: { color: textColor, callback: v => 'R$ ' + (v / 1000).toFixed(0) + 'k' },
          grid: { color: gridColor }
        },
        y: {
          title: { display: true, text: 'Margem (%)', color: textColor },
          min: 0,
          max: Math.max(medMargem * 2, 10),
          ticks: { color: textColor, callback: v => v + '%' },
          grid: { color: gridColor }
        }
      }
    },
    plugins: [{
      id: 'medianLines',
      afterDraw(chart) {
        const { ctx, chartArea, scales } = chart;
        if (!scales.x || !scales.y) return;
        ctx.save();
        ctx.setLineDash([6, 4]);
        ctx.strokeStyle = isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.25)';
        ctx.lineWidth = 1.5;
        const xPos = scales.x.getPixelForValue(medReceita);
        if (Number.isFinite(xPos)) { ctx.beginPath(); ctx.moveTo(xPos, chartArea.top); ctx.lineTo(xPos, chartArea.bottom); ctx.stroke(); }
        const yPos = scales.y.getPixelForValue(medMargem);
        if (Number.isFinite(yPos)) { ctx.beginPath(); ctx.moveTo(chartArea.left, yPos); ctx.lineTo(chartArea.right, yPos); ctx.stroke(); }
        ctx.restore();
      }
    }]
  });

  const tbody = document.getElementById('rentabilidadeBody');
  if (!tbody) return;
  tbody.innerHTML = '';

  let allClients = [...rentData.clientes].sort((a, b) => {
    const col = rentabilidadeSort.col;
    const dir = rentabilidadeSort.dir === 'asc' ? 1 : -1;
    if (col === 'cliente' || col === 'status') return dir * a[col].localeCompare(b[col]);
    return dir * ((Number(a[col]) || 0) - (Number(b[col]) || 0));
  });
  // Fixa o cliente selecionado no topo da tabela
  if (selectedRentabilidadeCliente) {
    const idx = allClients.findIndex(c => c.cliente === selectedRentabilidadeCliente);
    if (idx > 0) {
      const [pinned] = allClients.splice(idx, 1);
      allClients.unshift(pinned);
    }
  }

  const insightPhrases = {
    'Cliente Ideal': 'Alta margem + alta receita - cliente premium',
    'Potencial de Expansao': 'Alta margem + baixa receita - oportunidade de expansao',
    'Baixo Impacto': 'Baixa margem + baixa receita - avaliar esforco',
    'Risco de Margem': 'Baixa margem + alta receita - revisar precificacao',
  };

  allClients.forEach(c => {
    const tr = document.createElement('tr');
    tr.dataset.cliente = c.cliente;
    tr.title = insightPhrases[c.status] || '';
    tr.style.cursor = 'pointer';
    if (c.cliente === selectedRentabilidadeCliente) tr.classList.add('selected');
    tr.addEventListener('click', () => {
      selectedRentabilidadeCliente = c.cliente;
      renderRentabilidade();
    });
    const sc = {
      'Cliente Ideal': ['#22c55e', 'rgba(34,197,94,0.12)'],
      'Potencial de Expansao': ['#facc15', 'rgba(250,204,21,0.12)'],
      'Baixo Impacto': ['#38bdf8', 'rgba(56,189,248,0.12)'],
      'Risco de Margem': ['#ef4444', 'rgba(239,68,68,0.12)'],
    }[c.status] || ['#6b7280', 'rgba(107,114,128,0.12)'];
    tr.innerHTML = `
      <td style="font-weight:600">${c.cliente}</td>
      <td>${fmtMoney.format(c.receita)}</td>
      <td>${fmtMoney.format(c.lucro)}</td>
      <td>${c.margem}%</td>
      <td>${c.pedidos}</td>
      <td>${fmtMoney.format(c.ticket_medio)}</td>
      <td><span class="badge" style="background:${sc[1]};color:${sc[0]}">${c.status}</span></td>`;
    tbody.appendChild(tr);
  });

  // Sort indicators + click binding
  const ths = document.querySelectorAll('#rentabilidadeHead th');
  ths.forEach(th => {
    const text = th.textContent.replace(/[▲▼]/g, '').trim();
    th.textContent = text;
    if (th.dataset.col === rentabilidadeSort.col) {
      th.textContent += rentabilidadeSort.dir === 'asc' ? ' ▲' : ' ▼';
    }
    th.onclick = () => sortRentabilidade(th.dataset.col);
  });

  // Insights (ordem: Ideais, Potenciais, Baixo Impacto, Risco)
  const insightsEl = document.getElementById('rentabilidadeInsights');
  if (insightsEl) {
    const ideal = allClients.filter(c => c.status === 'Cliente Ideal').length;
    const expansao = allClients.filter(c => c.status === 'Potencial de Expansao').length;
    const baixo = allClients.filter(c => c.status === 'Baixo Impacto').length;
    const risco = allClients.filter(c => c.status === 'Risco de Margem').length;
    insightsEl.innerHTML = `
      <div class="insight-cards">
        <div class="insight-card" style="border-left-color:#22c55e;background:rgba(34,197,94,0.07)">
          <span class="insight-count" style="color:#22c55e">${ideal}</span>
          <span class="insight-label" style="color:#22c55e">Clientes Ideais</span>
        </div>
        <div class="insight-card" style="border-left-color:#eab308;background:rgba(250,204,21,0.07)">
          <span class="insight-count" style="color:#eab308">${expansao}</span>
          <span class="insight-label" style="color:#eab308">Potenciais Expansão</span>
        </div>
        <div class="insight-card" style="border-left-color:#38bdf8;background:rgba(56,189,248,0.07)">
          <span class="insight-count" style="color:#38bdf8">${baixo}</span>
          <span class="insight-label" style="color:#38bdf8">Baixo Impacto</span>
        </div>
        <div class="insight-card" style="border-left-color:#ef4444;background:rgba(239,68,68,0.07)">
          <span class="insight-count" style="color:#ef4444">${risco}</span>
          <span class="insight-label" style="color:#ef4444">Risco de Margem</span>
        </div>
      </div>
    `;
  }

  renderMargemMensal();
}

async function renderMargemMensal() {
  const card = document.getElementById('margemMensalCard');
  const title = document.getElementById('margemMensalTitle');
  const canvas = document.getElementById('margemMensalChart');
  if (!card || !title || !canvas) return;

  let dados = null;

  if (selectedRentabilidadeCliente) {
    // Fetch data for the selected client
    const params = new URLSearchParams();
    const fe = document.getElementById('filterEmpresa')?.value;
    const fn = document.getElementById('filterNatureza')?.value;
    const fa = document.getElementById('filterAno')?.value;
    const fm = document.getElementById('filterMes')?.value;
    const fp = document.getElementById('filterProduto')?.value;
    if (fe && fe !== 'TODAS') params.set('empresa', fe);
    if (fn && fn !== 'TODOS') params.set('natureza', fn);
    if (fa && fa !== 'TODOS') params.set('ano', fa);
    if (fm && fm !== 'TODOS') params.set('mes', fm);
    if (fp && fp !== 'TODOS') params.set('produto', fp);
    if (CLICK_FILTERS.uf) params.set('uf', CLICK_FILTERS.uf);
    if (CLICK_FILTERS.categoria) params.set('categoria', CLICK_FILTERS.categoria);
    if (CLICK_FILTERS.dia) params.set('dia', CLICK_FILTERS.dia);
    if (CLICK_FILTERS.dia_semana !== null) params.set('dia_semana', CLICK_FILTERS.dia_semana);
    params.set('cliente_margem', selectedRentabilidadeCliente);
    try {
      const resp = await fetch('/api/dados?' + params.toString());
      const json = await resp.json();
      dados = json.margem_mensal;
      title.textContent = `Margem % Mensal: ${selectedRentabilidadeCliente}`;
    } catch {
      dados = null;
    }
  } else {
    dados = DASHBOARD_DATA?.margem_mensal;
    title.textContent = 'Margem % Mensal - Todos os Clientes';
  }

  if (!dados || !dados.some(v => v !== null)) {
    card.style.display = 'none';
    return;
  }
  card.style.display = 'block';

  if (charts.margemMensal) charts.margemMensal.destroy();

  const labels = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const textColor = getTextColor();
  const gridColor = getGridColor();

  const hasData = dados.map((v, i) => v !== null ? i : -1).filter(i => i >= 0);
  const minVal = hasData.length > 0 ? Math.min(...hasData.map(i => dados[i])) : 0;
  const maxVal = hasData.length > 0 ? Math.max(...hasData.map(i => dados[i])) : 100;
  const yMin = Math.max(0, Math.floor((minVal - 5) / 5) * 5);
  const yMax = Math.ceil((maxVal + 5) / 5) * 5;

  charts.margemMensal = new Chart(canvas.getContext('2d'), {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        label: 'Margem %',
        data: dados,
        backgroundColor: dados.map(v => v !== null ? '#3B82F6' : 'transparent'),
        borderColor: dados.map(v => v !== null ? '#3B82F6' : 'transparent'),
        borderWidth: 0,
        borderRadius: 4,
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => ctx.raw !== null ? `Margem: ${ctx.raw}%` : 'Sem dados'
          }
        },
        datalabels: {
          display: ctx => ctx.raw !== null,
          anchor: 'end',
          align: 'end',
          color: textColor,
          font: { weight: '600', size: 10 },
          formatter: v => v !== null ? v + '%' : ''
        }
      },
      scales: {
        x: {
          ticks: { color: textColor },
          grid: { display: false }
        },
        y: {
          min: yMin,
          max: yMax,
          ticks: { color: textColor, callback: v => v + '%' },
          grid: { color: gridColor }
        }
      }
    }
  });
}

async function aplicarFiltros() {
    const emp = document.getElementById('filterEmpresa')?.value;
    const natureza = document.getElementById('filterNatureza')?.value;
    const tipoPessoa = document.getElementById('filterTipoPessoa')?.value;
  const ano = document.getElementById('filterAno')?.value;
  const mes = document.getElementById('filterMes')?.value;
  const prod = document.getElementById('filterProduto')?.value;
  const allCbs = document.querySelectorAll('#clienteOptions .multiselect-option input[type="checkbox"]');
  const checkedCbs = document.querySelectorAll('#clienteOptions .multiselect-option input[type="checkbox"]:checked');
  let cli = '';
  if (checkedCbs.length === 0) cli = '__NONE__';
  else if (checkedCbs.length < allCbs.length) cli = Array.from(checkedCbs).map(cb => cb.value).join(',');

  const params = new URLSearchParams();
    if (emp && emp !== 'TODAS') params.append('empresa', emp);
    if (natureza && natureza !== 'TODOS') params.append('natureza', natureza);
    if (tipoPessoa && tipoPessoa !== 'TODOS') params.append('tipo_pessoa', tipoPessoa);
  if (ano && ano !== 'TODOS') params.append('ano', ano);
  if (mes && mes !== 'TODOS') params.append('mes', mes);
  if (prod && prod !== 'TODOS') params.append('produto', prod);
  if (cli) params.append('cliente', cli);

  if (CLICK_FILTERS.uf) params.append('uf', CLICK_FILTERS.uf);
  if (CLICK_FILTERS.categoria) params.append('categoria', CLICK_FILTERS.categoria);
  if (CLICK_FILTERS.dia) params.append('dia', CLICK_FILTERS.dia);
  if (CLICK_FILTERS.dia_semana !== null) params.append('dia_semana', CLICK_FILTERS.dia_semana);

  DASHBOARD_DATA = await dataService.fetchAllData(params);
  if (DASHBOARD_DATA) {
    renderKPIs();
    renderCharts();
    selectedTop20Cliente = null;
    selectedRentabilidadeCliente = null;
    renderTop20Clientes();
    renderRentabilidade();
    loadMap(params);
  }
}

async function loadMap(params) {
  MAPA_DATA = await dataService.fetchMapData(params);
  if (MAPA_DATA) desenharMapa();
}

function desenharMapa() {
  if (!MAPA_DATA) return;

  var container = document.getElementById('mapaBrasil');
  if (!container) return;
  container.innerHTML = '';

  var width = container.clientWidth || 960;
  var height = container.clientHeight || 380;

  var svg = d3.select('#mapaBrasil').append('svg')
  .attr('width', width).attr('height', height);

  var projection = d3.geo.mercator()
  .center([-53, -15.5])
  .scale(600)
  .translate([width / 2, height / 1.8]);

  var path = d3.geo.path().projection(projection);

  var dados = MAPA_DATA.dados_por_uf;
  var maxVal = MAPA_DATA.max_valor || 1;
  var isDark = document.documentElement.getAttribute('data-theme') === 'dark';

  var allValues = Object.keys(dados).map(function(uf) { return dados[uf].valor; }).sort(d3.ascending);

  var colorRange = isDark
  ? ['#1a3a2a', '#1e5235', '#236b40', '#2d8a4e', '#38a864', '#4dc780', '#7dd9a0', '#b0e8c4', '#d5f2e0']
  : ['#e6f5ec', '#c3e6d0', '#9dd8b3', '#78c996', '#53ba79', '#3aa860', '#2d9050', '#1f7840', '#125f30'];

  var color;
  if (allValues.length > 1) {
    color = d3.scale.quantile()
    .domain(allValues)
    .range(colorRange);
  } else {
    color = function() { return colorRange[colorRange.length - 1]; };
    color.range = function() { return colorRange; };
  }

  var noDataColor = isDark ? '#1e293b' : '#cbd5e1';
  var strokeColor = isDark ? '#475569' : '#94a3b8';

  var legendBar = document.getElementById('mapLegendBar');
  if (legendBar) {
    var colors = color.range();
    legendBar.style.background = 'linear-gradient(to right, ' + colors.join(', ') + ')';
  }

  var cardHeader = document.getElementById('mapInfoCardHeader');
  var cardBody = document.getElementById('mapInfoCardBody');

  function updateCard(nome, uf, info) {
    if (cardHeader) {
      cardHeader.textContent = info ? (info.nome || uf) : nome;
    }
    if (cardBody) {
      if (info) {
        cardBody.innerHTML =
          '<div class="map-info-row"><span class="map-info-label">Valor Total</span><span class="map-info-value">R$ ' + info.valor.toLocaleString('pt-BR', { minimumFractionDigits: 2 }) + '</span></div>' +
          '<div class="map-info-row"><span class="map-info-label">Total Notas</span><span class="map-info-value">' + info.notas.toLocaleString('pt-BR') + '</span></div>' +
          '<div class="map-info-row"><span class="map-info-label">Participacao</span><span class="map-info-value map-info-pct">' + info.porcentagem + '%</span></div>';
      } else {
        cardBody.innerHTML = '<div class="map-info-row"><span class="map-info-value" style="color:var(--text-secondary);font-style:italic">Sem vendas</span></div>';
      }
    }
  }

  function renderStates(geoData) {
    var states = geoData.features;

    svg.selectAll("path")
    .data(states)
    .enter().append("path")
    .attr("class", function(d) {
      var nome = d.properties.name;
      var uf = ESTADO_UF_MAP[nome];
      return dados[uf] ? 'state-path' : 'state-path no-data';
    })
    .attr("d", path)
    .style("fill", function(d) {
      var nome = d.properties.name;
      var uf = ESTADO_UF_MAP[nome];
      var info = dados[uf];
      return info ? color(info.valor) : noDataColor;
    })
    .style("stroke", strokeColor)
    .style("stroke-width", 0.8)
    .on("mouseover", function(d) {
      d3.select(this).style("stroke", isDark ? '#10b981' : '#059669').style("stroke-width", 2);
      var nome = d.properties.name;
      var uf = ESTADO_UF_MAP[nome];
      var info = dados[uf];
      updateCard(nome, uf, info);
    })
    .on("mouseout", function() {
      d3.select(this).style("stroke", strokeColor).style("stroke-width", 0.8);
      if (cardHeader) cardHeader.textContent = 'Passe o mouse sobre um estado';
      if (cardBody) cardBody.innerHTML = '<div class="map-info-placeholder"><span style="color:var(--text-secondary);font-size:13px">Explore o mapa para ver os dados detalhados</span></div>';
    })
    .on("click", function(d) {
      var nome = d.properties.name;
      var uf = ESTADO_UF_MAP[nome];
      if (uf && dados[uf]) {
        CLICK_FILTERS.uf = (CLICK_FILTERS.uf === uf) ? null : uf;
        aplicarFiltros();
      }
    });

    renderRankEstados();
  }

  if (GEOJSON_CACHE) { renderStates(GEOJSON_CACHE); return; }

  d3.json("https://raw.githubusercontent.com/codeforamerica/click_that_hood/master/public/data/brazil-states.geojson", function(error, data) {
    if (error) { console.error("Erro ao carregar o mapa:", error); return; }
    GEOJSON_CACHE = data;
    renderStates(data);
  });
}

function renderRankEstados() {
  if (!MAPA_DATA) return;

  var dados = MAPA_DATA.dados_por_uf;
  var maxVal = MAPA_DATA.max_valor || 1;

  var ranking = Object.keys(dados)
    .map(function(uf) { var info = dados[uf]; return { uf: uf, nome: info.nome, valor: info.valor, pct: info.porcentagem }; })
    .sort(function(a, b) { return b.valor - a.valor; })
    .slice(0, 10);

  var rankDiv = document.getElementById('mapRank');
  if (!rankDiv) return;
  rankDiv.innerHTML = ranking.map(function(item, i) {
    return '<div class="map-rank-item">' +
      '<div style="flex:1">' +
      '<span style="color:var(--primary);font-weight:700;margin-right:8px">' + (i + 1) + '.</span>' +
      '<span style="font-weight:600">' + item.nome + '</span>' +
      '<span style="color:var(--text-secondary);margin-left:6px">(' + item.uf + ')</span>' +
      '</div>' +
      '<div style="flex:1;padding:0 12px">' +
      '<div class="map-rank-bar" style="width:' + (item.valor / maxVal * 100).toFixed(1) + '%"></div>' +
      '</div>' +
      '<div style="text-align:right;min-width:120px">' +
      '<div style="font-weight:600">R$ ' + item.valor.toLocaleString('pt-BR', { minimumFractionDigits: 2 }) + '</div>' +
      '<div style="color:var(--text-secondary);font-size:11px">' + item.pct + '%</div>' +
      '</div></div>';
  }).join('');
}

var selectedTop20Cliente = null;

function renderTop20Clientes() {
  var data = DASHBOARD_DATA;
  if (!data) return;
  var top20 = data.top20_clientes || [];
  var mix = data.mix_por_cliente || {};
  var container = document.getElementById('top20ClientesList');
  if (!container) return;
  container.innerHTML = top20.map(function(c, i) {
    var pct = (top20[0] && top20[0].valor) ? (c.valor / top20[0].valor * 100).toFixed(1) : 0;
    var sharePct = (c.porcentagem || 0).toFixed(2);
    var isActive = selectedTop20Cliente === c.cliente;
    return '<div class="top20-item' + (isActive ? ' active' : '') + '" data-cliente="' + c.cliente.replace(/"/g, '&quot;') + '">' +
      '<div class="top20-rank">' + (i + 1) + '</div>' +
      '<div class="top20-info">' +
        '<div class="top20-name">' + c.cliente + '</div>' +
        '<div class="top20-meta">' + fmtNum.format(c.notas) + ' notas / ' + fmtNum.format(c.caixas || 0) + ' CX</div>' +
      '</div>' +
      '<div class="top20-value">' +
        '<div class="top20-amount">' + fmtMoney.format(c.valor) + ' <span class="top20-pct">' + sharePct + '%</span></div>' +
        '<div class="top20-bar-wrap"><div class="top20-bar" style="width:' + pct + '%"></div></div>' +
      '</div></div>';
  }).join('');
  container.querySelectorAll('.top20-item').forEach(function(el) {
    el.addEventListener('click', function() {
      var nome = el.getAttribute('data-cliente');
      selectedTop20Cliente = (selectedTop20Cliente === nome) ? null : nome;
      renderTop20Clientes();
      renderMixCliente(selectedTop20Cliente);
    });
  });
  if (selectedTop20Cliente) renderMixCliente(selectedTop20Cliente);
}

function renderMixCliente(nome) {
  var nameEl = document.getElementById('mixClienteName');
  var bodyEl = document.getElementById('mixClienteBody');
  if (!nameEl || !bodyEl) return;
  if (!nome) {
    nameEl.textContent = '';
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Clique em um cliente ao lado para ver seu mix</span></div>';
    return;
  }
  var mix = (DASHBOARD_DATA.mix_por_cliente || {})[nome] || [];
  nameEl.textContent = '- ' + nome;
  if (!mix.length) {
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Sem dados de mix para este cliente</span></div>';
    return;
  }
  var maxVal = mix[0].valor || 1;
  bodyEl.innerHTML = mix.map(function(p) {
    var pct = (p.valor / maxVal * 100).toFixed(1);
    return '<div class="mix-row">' +
      '<div class="mix-prod-name">' + p.produto + '</div>' +
      '<div class="mix-prod-cat">' + (p.categoria || '') + '</div>' +
      '<div class="mix-bar-wrap"><div class="mix-bar" style="width:' + pct + '%"></div></div>' +
      '<div class="mix-prod-vals">' +
        '<span>R$ ' + fmtMoney.format(p.valor) + '</span>' +
        '<span style="color:var(--text-secondary);margin-left:8px">' + fmtNum.format(p.caixas || 0) + ' CX</span>' +
      '</div></div>';
  }).join('');
}

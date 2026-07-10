//========================================
// vendas.js
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

const fmtNum = new Intl.NumberFormat('pt-BR');
const MESES_PT = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

let VENDAS_DATA = null;
let MAPA_DATA = null;
let GEOJSON_CACHE_VENDAS = null;
let CLICK_FILTERS = { uf: null, categoria: null, dia: null, dia_semana: null };
let charts = {};
let _vendasThemeHandler = null;

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
        <div id="vendas-filters" style="margin-bottom:20px"></div>
        <div id="kpi-vendas" class="kpi-cards"></div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:show-chart" alt=""> Evolucao Mensal de Caixas</h3>
  <div class="chart-container"><canvas id="vendasEvolucaoChart"></canvas></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:pie-chart" alt=""> Participacao de Mercado: FILIAL_B vs FILIAL</h3>
  <div class="chart-container"><canvas id="vendasMarketShareChart"></canvas></div>
  </div>
  </div>

  <div class="grid-3" style="margin-bottom:20px">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:groups" alt=""> Top 30 Clientes por Caixas</h3>
  <div id="vendasTop20List" class="top20-list"></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:inventory-2" alt=""> Mix de Produtos <span id="vendasMixName" style="color:#10b981;font-size:13px"></span></h3>
  <div id="vendasMixBody" class="mix-body">
  <div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Clique em um cliente ao lado para ver seu mix</span></div>
  </div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:lightbulb" alt=""> Produtos Sugeridos <span id="vendasSugeridosName" style="color:#f59e0b;font-size:13px"></span></h3>
  <div id="vendasSugeridosBody" class="mix-body">
  <div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Selecione um cliente para ver sugestoes</span></div>
  </div>
  </div>
  </div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:category" alt=""> Caixas por Categoria</h3>
  <div class="chart-container">
  <canvas id="vendasRankCategoriaChart"></canvas>
  <div id="vendasRankCategoriaEmpty" class="empty-chart-state" style="display:none;align-items:center;justify-content:center;height:200px;color:var(--text-secondary);font-size:13px">Nenhuma categoria encontrada para o período selecionado</div>
  </div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:leaderboard" alt=""> Top 10 Produtos (Caixas)</h3>
  <div class="chart-container"><canvas id="vendasTop10Chart"></canvas></div>
  </div>
  </div>

  <div class="grid-2" style="margin-bottom:20px">
  <div class="card map-container">
  <h3><img class="icon section-icon" data-icon="material-symbols:map" alt=""> Mapa de Caixas por Estado</h3>
  <div style="display:flex;gap:16px;align-items:stretch">
  <div style="flex:1;position:relative;min-width:0">
  <div id="vendasMapaBrasil" style="position:relative;width:100%;height:380px;"></div>
  <div class="map-legend">
  <span>Menor</span>
  <div class="map-legend-bar" id="vendasMapLegendBar"></div>
  <span>Maior</span>
  </div>
  </div>
  <div class="map-info-card" id="vendasMapInfoCard">
  <div class="map-info-card-header" id="vendasMapInfoCardHeader">Passe o mouse sobre um estado</div>
  <div class="map-info-card-body" id="vendasMapInfoCardBody">
  <div class="map-info-placeholder"><span style="color:var(--text-secondary);font-size:13px">Hover no mapa para ver detalhes</span></div>
  </div>
  </div>
  </div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:leaderboard" alt=""> Ranking por Estado (Caixas)</h3>
  <div id="vendasMapRank" class="map-rank"></div>
  </div>
  </div>

  <div class="grid-2">
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:calendar-today" alt=""> Evolucao Diaria de Caixas</h3>
  <div class="chart-container"><canvas id="vendasEvolucaoDiariaChart"></canvas></div>
  </div>
  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:event-repeat" alt=""> Rank: Melhor Dia da Semana</h3>
  <div class="chart-container"><canvas id="vendasRankSemanaChart"></canvas></div>
  </div>
  </div>

  <div class="card">
  <h3><img class="icon section-icon" data-icon="material-symbols:table-rows" alt=""> Transacoes Recentes</h3>
            <div class="table-wrapper">
                <table id="vendasTransacoesTable">
                    <thead>
                        <tr><th>Data</th><th>NFe</th><th>Produto</th><th>Cliente</th><th>Cidade</th><th>UF</th><th>Litros</th><th>Un.</th><th>Emp.</th></tr>
                    </thead>
                    <tbody id="vendasTransacoesBody"></tbody>
                </table>
            </div>
        </div>
    </div>
    `;
}

export async function renderVendasPage(appRoot) {
    try {
        const paramsIniciais = new URLSearchParams();
        paramsIniciais.set('ano', String(new Date().getFullYear()));
        VENDAS_DATA = await dataService.fetchVendasData(paramsIniciais);
        if (!VENDAS_DATA) {
            throw new Error('Nao foi possivel carregar os dados de vendas.');
        }
        MAPA_DATA = VENDAS_DATA.mapa_caixas || null;
        appRoot.innerHTML = getPageHTML();
      renderFilters();
      renderKPIs();
      requestAnimationFrame(() => {
          renderCharts();
          requestAnimationFrame(() => {
              renderVendasTop20();
              renderTabela(VENDAS_DATA.transacoes_recentes || []);
              desenharMapa();
              updateAllIcons();
          });
      });
    } catch (err) {
        console.error('[Vendas] Erro:', err);
        appRoot.innerHTML = `<div class="card"><h3>Erro ao carregar dados</h3><p style="color:var(--text-secondary)">${err.message}</p></div>`;
    }

    if (_vendasThemeHandler) window.removeEventListener('Dashboard:theme-change', _vendasThemeHandler);
    _vendasThemeHandler = onThemeChange;
    window.addEventListener('Dashboard:theme-change', _vendasThemeHandler);
}

function onThemeChange() {
    if (VENDAS_DATA) {
        setTimeout(() => {
            renderCharts();
            if (MAPA_DATA) desenharMapa();
        }, 100);
    }
}

function renderFilters() {
    const f = VENDAS_DATA.filtros || {};
    const mesesPt = ['', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

    const container = document.getElementById('vendas-filters');
    if (!container) return;

    container.innerHTML = `
    <div class="controls" style="flex-wrap:wrap;gap:10px;justify-content:flex-start">
        <select class="filter-empresa" id="vFilterEmpresa">
            <option value="TODAS">Todas as Empresas</option>
            ${(f.empresas || ['FILIAL_B', 'FILIAL']).map(e => `<option value="${e}">${e}</option>`).join('')}
        </select>
        <select class="filter-empresa" id="vFilterNatureza" style="min-width:110px">
            <option value="Venda" selected>Venda</option>
            <option value="TODOS">Todas Naturezas</option>
        </select>
        <select class="filter-empresa" id="vFilterTipoPessoa" style="min-width:110px">
            <option value="TODOS">CPF/CNPJ</option>
<option value="Física">CPF</option>
      <option value="Jurídica">CNPJ</option>
        </select>
        <select class="filter-empresa" id="vFilterAno" style="min-width:80px">
            <option value="TODOS">Todos Anos</option>
            ${(f.anos || []).map(a => `<option value="${a}"${a == new Date().getFullYear() ? ' selected' : ''}>${a}</option>`).join('')}
        </select>
        <select class="filter-empresa" id="vFilterMes" style="min-width:100px">
            <option value="TODOS">Todos Meses</option>
            ${Array.from({length:12}, (_, i) => `<option value="${i+1}">${mesesPt[i+1]}</option>`).join('')}
        </select>
        <select class="filter-empresa" id="vFilterProduto" style="min-width:140px">
            <option value="TODOS">Todos Produtos</option>
            ${(f.produtos || []).map(p => `<option value="${p}">${p.length > 40 ? p.slice(0,38) + '...' : p}</option>`).join('')}
        </select>
        <div class="multiselect-container" id="vClienteContainer">
            <div class="multiselect-trigger" id="vClienteTrigger">
                <img class="icon multiselect-trigger-icon" data-icon="material-symbols:search" alt="">
                <span class="multiselect-label" id="vClienteLabel">Todos Clientes</span>
                <img class="icon multiselect-arrow" data-icon="material-symbols:arrow-drop-down-rounded" alt="">
            </div>
            <div class="multiselect-dropdown" id="vClienteDropdown">
                <input type="text" class="multiselect-search" id="vClienteSearchInput" placeholder="Buscar cliente...">
                <label class="multiselect-option select-all">
                    <input type="checkbox" id="vClienteSelectAll" checked> Selecionar Todos
                </label>
                <div class="multiselect-options" id="vClienteOptions"></div>
            </div>
        </div>
    </div>
    `;

    const optionsDiv = document.getElementById('vClienteOptions');
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

    ['vFilterEmpresa', 'vFilterNatureza', 'vFilterTipoPessoa', 'vFilterAno', 'vFilterMes', 'vFilterProduto'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.addEventListener('change', () => aplicarFiltros());
    });

    const trigger = document.getElementById('vClienteTrigger');
    const dropdown = document.getElementById('vClienteDropdown');
    const searchInput = document.getElementById('vClienteSearchInput');
    const selectAll = document.getElementById('vClienteSelectAll');
    const optionsContainer = document.getElementById('vClienteOptions');

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
        const cc = document.getElementById('vClienteContainer');
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
        const label = document.getElementById('vClienteLabel');
        if (checked.length === options.length) label.textContent = 'Todos Clientes';
        else if (checked.length === 0) label.textContent = 'Nenhum Cliente';
        else if (checked.length === 1) { const name = checked[0].querySelector('input[type="checkbox"]').value; label.textContent = name.length > 22 ? name.slice(0,20) + '...' : name; }
        else label.textContent = checked.length + ' clientes';
    }
}

function renderKPIs() {
    const k = VENDAS_DATA.kpis;
    const vol = VENDAS_DATA.volume || {};
    const container = document.getElementById('kpi-vendas');
    if (!container || !k) return;

    const volEmpresa = vol.por_empresa || {};
    const volTrend = Object.keys(volEmpresa).length > 0
        ? Object.keys(volEmpresa).map(e => {
            const v = volEmpresa[e];
            return `${e}: ${fmtNum.format(v.caixas_12m)} CX (${(v.share_12m || 0).toFixed(1)}%)`;
        }).join('<br>')
        : 'Ultimos 12 meses';

    container.innerHTML = `
    <div class="kpi-card faturamento">
        <div class="kpi-header"><span class="label">Total de Caixas</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:inventory-2" alt=""></div></div>
        <span class="value">${fmtNum.format(k.total_caixas || 0)}</span>
        <span class="trend">CX Vendidas</span>
    </div>
    <div class="kpi-card custos">
        <div class="kpi-header"><span class="label">Total de Litros</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:water-drop" alt=""></div></div>
        <span class="value">${fmtNum.format(k.total_litros || 0)} L</span>
        <span class="trend">Volume em Litros</span>
    </div>
    <div class="kpi-card ticket">
        <div class="kpi-header"><span class="label">Media CX / Nota</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:scale" alt=""></div></div>
        <span class="value">${fmtNum.format(k.media_cx_nota || 0)}</span>
        <span class="trend">CX por Nota Fiscal</span>
    </div>
    <div class="kpi-card notas">
        <div class="kpi-header"><span class="label">Notas / Unidades</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:description-outline" alt=""></div></div>
        <span class="value">${fmtNum.format(k.total_notas || 0)} / ${fmtNum.format(k.total_unidades || 0)}</span>
        <span class="trend">NOTAS / UNIDADES</span>
    </div>
    <div class="kpi-card pm">
        <div class="kpi-header"><span class="label">Volume 12 Meses</span><div class="kpi-icon-bg"><img class="icon kpi-icon" data-icon="material-symbols:analytics" alt=""></div></div>
        <span class="value">${fmtNum.format(Object.values(volEmpresa).reduce((s, v) => s + (v.caixas_12m || 0), 0))} CX</span>
        <span class="trend" id="vKpiVolTrend">${volTrend}</span>
    </div>
    `;
    updateAllIcons();
}

function renderCharts(dataOverride) {
    const DDATA = dataOverride || VENDAS_DATA;
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
        const el = document.getElementById(`vFilter${dimension}`);
        const clickVal = CLICK_FILTERS[dimension.toLowerCase()];
        const activeVal = el ? el.value : clickVal;
        if (!activeVal || activeVal === 'TODOS' || activeVal === 'TODAS' || activeVal === '') return defaultColor;
        if (label.toString() === activeVal.toString()) return defaultColor;
        return isDark ? '#334155' : '#E2E8F0';
    };

    const fmtCx = (v) => {
        if (v >= 1000) return (v / 1000).toFixed(1) + 'k';
        return v.toString();
    };
    const destroy = (name) => { if (charts[name]) { charts[name].destroy(); charts[name] = null; } };

    // 1. Evolucao Mensal (Caixas)
    destroy('evolucao');
    let anoAtual = DDATA.evolucao_mensal.ano_atual || new Date().getFullYear();
    let evolData = DDATA.evolucao_mensal.data || [];
    let evolDataAnterior = DDATA.evolucao_mensal.data_anterior || [];

    if (document.getElementById('vendasEvolucaoChart')) {
        charts.evolucao = new Chart(document.getElementById('vendasEvolucaoChart').getContext('2d'), {
            type: 'line',
            data: {
                labels: MESES_PT,
                datasets: [{
                    label: 'Total',
                    data: evolData.map((v, i) => (v || 0) + (evolDataAnterior[i] || 0)),
                    borderColor: palette[4], backgroundColor: palette[4],
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
                        const el = document.getElementById('vFilterMes');
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
                                if (dsIdx === 0) return `Total: ${fmtNum.format(value)} CX (100%)`;
                                const pct = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                                return `${context.dataset.label}: ${fmtNum.format(value)} CX (${pct}%)`;
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
                    y: { ticks: { callback: fmtCx, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
                    x: { ticks: { color: getTextColor() }, grid: { display: false } }
                }
            }
        });
    }

    // 2. Market Share (Caixas)
    destroy('marketShare');
    if (document.getElementById('vendasMarketShareChart')) {
        charts.marketShare = new Chart(document.getElementById('vendasMarketShareChart').getContext('2d'), {
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
                        const el = document.getElementById('vFilterEmpresa');
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
                                return `${context.label}: ${fmtNum.format(value)} CX (${pct}%)`;
                            }
                        }
                    }
                }
            }
        });
    }

    // 3. Top 10 Produtos (Caixas)
    destroy('top10');
    if (document.getElementById('vendasTop10Chart')) {
        charts.top10 = new Chart(document.getElementById('vendasTop10Chart').getContext('2d'), {
            type: 'bar',
            data: {
                labels: DDATA.top10.labels,
                datasets: [{
                    label: 'Caixas', data: DDATA.top10.data,
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
                        const el = document.getElementById('vFilterProduto');
                        el.value = (el.value === label) ? 'TODOS' : label;
                        aplicarFiltros();
                    }
                },
                plugins: {
                    legend: { display: false }, datalabels: { display: true,
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
                                return `${context.label}: ${fmtNum.format(value)} CX (${pct}%)`;
                            }
                        }
                    }
                },
                scales: {
                    x: { ticks: { callback: fmtCx, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
                    y: { ticks: { color: getTextColor() }, grid: { display: false } }
                }
            }
        });
    }

    // 4. Evolucao Diaria (Caixas)
    destroy('evolDiaria');
    const dData = DDATA.evolucao_diaria;
    if (document.getElementById('vendasEvolucaoDiariaChart')) {
        charts.evolDiaria = new Chart(document.getElementById('vendasEvolucaoDiariaChart').getContext('2d'), {
            type: 'bar',
            data: {
                labels: dData.labels,
                datasets: [{
                    label: 'Caixas diarias', data: dData.data,
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
                    legend: { display: false }, datalabels: { display: true,
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
                                return `Caixas: ${fmtNum.format(value)} (${pct}%)`;
                            }
                        }
                    }
                },
                scales: {
                    y: { ticks: { callback: fmtCx, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
                    x: { ticks: { color: getTextColor(), font: { size: 9 } }, grid: { display: false } }
                }
            }
        });
    }

    // 5. Rank Dia da Semana (Caixas)
    destroy('rankSemana');
    const rsData = DDATA.rank_semana;
    if (document.getElementById('vendasRankSemanaChart')) {
        charts.rankSemana = new Chart(document.getElementById('vendasRankSemanaChart').getContext('2d'), {
            type: 'bar',
            data: {
                labels: rsData.labels,
                datasets: [{
                    label: 'Caixas', data: rsData.data,
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
                    legend: { display: false }, datalabels: { display: true,
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
                                return `${context.label}: ${fmtNum.format(value)} CX (${pct}%)`;
                            }
                        }
                    }
                },
                scales: {
                    y: { max: Math.ceil(Math.max(...rsData.data) * 1.2 / 1000) * 1000, ticks: { callback: fmtCx, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
                    x: { ticks: { color: getTextColor() }, grid: { display: false } }
                }
            }
        });
    }

    // 6. Rank de Categoria (Caixas)
    destroy('rankCategoria');
    const rcData = DDATA.rank_categoria;
    const catCanvas = document.getElementById('vendasRankCategoriaChart');
    const catEmpty = document.getElementById('vendasRankCategoriaEmpty');
    if (rcData && rcData.labels && rcData.labels.length > 0 && catCanvas) {
        if (catEmpty) catEmpty.style.display = 'none';
        catCanvas.style.display = '';
        charts.rankCategoria = new Chart(catCanvas.getContext('2d'), {
            type: 'bar',
            data: {
                labels: rcData.labels,
                datasets: [{
                    label: 'Caixas', data: rcData.data,
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
                    legend: { display: false }, datalabels: { display: true,
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
                                return `${context.label}: ${fmtNum.format(value)} CX (${pct}%)`;
                            }
                        }
                    }
                },
                scales: {
                    x: { ticks: { callback: fmtCx, color: getTextColor() }, grid: { color: getGridColor(), drawTicks: false } },
                    y: { ticks: { color: getTextColor() }, grid: { display: false } }
                }
            }
        });
    } else if (catEmpty) {
        catEmpty.style.display = 'flex';
        if (catCanvas) catCanvas.style.display = 'none';
    }
}

function renderTabela(rows) {
    const tbody = document.getElementById('vendasTransacoesBody');
    if (!tbody) return;
    const data = (rows || VENDAS_DATA?.transacoes_recentes || []);
    tbody.innerHTML = '';
    if (!data.length) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align:center;color:var(--text-secondary);padding:24px;font-size:13px">Nenhuma transação encontrada para o período selecionado</td></tr>';
        return;
    }
    data.slice(0, 50).forEach(t => {
        const tr = document.createElement('tr');
        const data = t['data_emissao'] || '';
        const dataFormatada = data ? data.split('-').reverse().join('/') : '';
        const nota = t['numero_nota'] || '';
        const produto = t['produto'] || '';
        const cliente = t['cliente'] || '';
        const cidade = t['cidade'] || '';
        const uf = t['uf'] || '';
    const litros = t['litros_produto'] || 0;
    const unidades = t['quantidade'] || 0;
    const empresa = t['empresa'] || '';
    tr.innerHTML = `<td>${dataFormatada}</td><td>${nota}</td><td>${produto}</td><td>${cliente}</td><td>${cidade}</td><td>${uf}</td><td>${fmtNum.format(litros)} L</td><td>${fmtNum.format(unidades)}</td><td><span class="badge badge-${empresa}">${empresa}</span></td>`;
        tbody.appendChild(tr);
    });
}

async function aplicarFiltros() {
    const emp = document.getElementById('vFilterEmpresa')?.value;
    const natureza = document.getElementById('vFilterNatureza')?.value;
    const tipoPessoa = document.getElementById('vFilterTipoPessoa')?.value;
    const ano = document.getElementById('vFilterAno')?.value;
    const mes = document.getElementById('vFilterMes')?.value;
    const prod = document.getElementById('vFilterProduto')?.value;
    const allCbs = document.querySelectorAll('#vClienteOptions .multiselect-option input[type="checkbox"]');
    const checkedCbs = document.querySelectorAll('#vClienteOptions .multiselect-option input[type="checkbox"]:checked');
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

    VENDAS_DATA = await dataService.fetchVendasData(params);
    if (VENDAS_DATA) {
    MAPA_DATA = VENDAS_DATA.mapa_caixas || null;
    renderKPIs();
    renderCharts();
    selectedVendasCliente = null;
    renderVendasTop20();
    renderTabela(VENDAS_DATA.transacoes_recentes || []);
    desenharMapa();
    }
}

function desenharMapa() {
  if (!MAPA_DATA) return;

  var container = document.getElementById('vendasMapaBrasil');
  if (!container) return;
  container.innerHTML = '';

  var width = container.clientWidth || 960;
  var height = container.clientHeight || 380;

  var svg = d3.select('#vendasMapaBrasil').append('svg')
  .attr('width', width).attr('height', height);

  var projection = d3.geo.mercator()
  .center([-53, -15.5])
  .scale(600)
  .translate([width / 2, height / 1.8]);

  var path = d3.geo.path().projection(projection);

  var dados = MAPA_DATA.dados_por_uf;
  var maxVal = MAPA_DATA.max_valor || 1;
  var isDark = document.documentElement.getAttribute('data-theme') === 'dark';

  var allValues = Object.keys(dados).map(function(uf) { return dados[uf].caixas; }).sort(d3.ascending);

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

  var legendBar = document.getElementById('vendasMapLegendBar');
  if (legendBar) {
    var colors = color.range();
    legendBar.style.background = 'linear-gradient(to right, ' + colors.join(', ') + ')';
  }

  var cardHeader = document.getElementById('vendasMapInfoCardHeader');
  var cardBody = document.getElementById('vendasMapInfoCardBody');

  function updateCard(nome, uf, info) {
    if (cardHeader) {
      cardHeader.textContent = info ? (info.nome || uf) : nome;
    }
    if (cardBody) {
      if (info) {
        cardBody.innerHTML =
          '<div class="map-info-row"><span class="map-info-label">Total Caixas</span><span class="map-info-value">' + fmtNum.format(info.caixas) + '</span></div>' +
          '<div class="map-info-row"><span class="map-info-label">Total Notas</span><span class="map-info-value">' + fmtNum.format(info.notas) + '</span></div>' +
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
      return info ? color(info.caixas) : noDataColor;
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
      if (cardBody) cardBody.innerHTML = '<div class="map-info-placeholder"><span style="color:var(--text-secondary);font-size:13px">Hover no mapa para ver detalhes</span></div>';
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

  if (GEOJSON_CACHE_VENDAS) { renderStates(GEOJSON_CACHE_VENDAS); return; }

  d3.json("https://raw.githubusercontent.com/codeforamerica/click_that_hood/master/public/data/brazil-states.geojson", function(error, data) {
    if (error) { console.error("Erro ao carregar o mapa:", error); return; }
    GEOJSON_CACHE_VENDAS = data;
    renderStates(data);
  });
}

function renderRankEstados() {
    if (!MAPA_DATA) return;

    var dados = MAPA_DATA.dados_por_uf;
    var maxVal = MAPA_DATA.max_valor || 1;

    var ranking = Object.keys(dados)
        .map(function(uf) { var info = dados[uf]; return { uf: uf, nome: info.nome, caixas: info.caixas, pct: info.porcentagem }; })
        .sort(function(a, b) { return b.caixas - a.caixas; })
        .slice(0, 10);

    var rankDiv = document.getElementById('vendasMapRank');
    if (!rankDiv) return;
    rankDiv.innerHTML = ranking.map(function(item, i) {
        return '<div class="map-rank-item">' +
            '<div style="flex:1">' +
            '<span style="color:var(--primary);font-weight:700;margin-right:8px">' + (i + 1) + '.</span>' +
            '<span style="font-weight:600">' + item.nome + '</span>' +
            '<span style="color:var(--text-secondary);margin-left:6px">(' + item.uf + ')</span>' +
            '</div>' +
            '<div style="flex:1;padding:0 12px">' +
            '<div class="map-rank-bar" style="width:' + (item.caixas / maxVal * 100).toFixed(1) + '%"></div>' +
            '</div>' +
            '<div style="text-align:right;min-width:120px">' +
            '<div style="font-weight:600">' + fmtNum.format(item.caixas) + ' CX</div>' +
            '<div style="color:var(--text-secondary);font-size:11px">' + item.pct + '%</div>' +
            '</div></div>';
    }).join('');
}

var selectedVendasCliente = null;

function renderVendasTop20() {
  var data = VENDAS_DATA;
  if (!data) return;
  var top20 = data.top20_clientes || [];
  var container = document.getElementById('vendasTop20List');
  if (!container) return;
  if (!top20.length) {
    container.innerHTML = '<div style="padding:24px;text-align:center;color:var(--text-secondary);font-size:13px">Nenhum cliente encontrado para o período selecionado</div>';
    return;
  }
  container.innerHTML = top20.map(function(c, i) {
    var maxCx = top20[0] ? top20[0].caixas : 1;
    var pct = (c.caixas / maxCx * 100).toFixed(1);
    var isActive = selectedVendasCliente === c.cliente;
    return '<div class="top20-item' + (isActive ? ' active' : '') + '" data-cliente="' + c.cliente.replace(/"/g, '&quot;') + '">' +
      '<div class="top20-rank">' + (i + 1) + '</div>' +
      '<div class="top20-info">' +
        '<div class="top20-name">' + c.cliente + '</div>' +
        '<div class="top20-meta">' + c.notas + ' notas</div>' +
      '</div>' +
      '<div class="top20-value">' +
        '<div class="top20-amount">' + fmtNum.format(c.caixas) + ' CX</div>' +
        '<div class="top20-bar-wrap"><div class="top20-bar" style="width:' + pct + '%"></div></div>' +
      '</div></div>';
  }).join('');
  container.querySelectorAll('.top20-item').forEach(function(el) {
    el.addEventListener('click', function() {
      var nome = el.getAttribute('data-cliente');
      selectedVendasCliente = (selectedVendasCliente === nome) ? null : nome;
      renderVendasTop20();
      renderVendasMix(selectedVendasCliente);
      renderVendasSugeridos(selectedVendasCliente);
    });
  });
  if (selectedVendasCliente) {
    renderVendasMix(selectedVendasCliente);
    renderVendasSugeridos(selectedVendasCliente);
  }
}

function renderVendasMix(nome) {
  var nameEl = document.getElementById('vendasMixName');
  var bodyEl = document.getElementById('vendasMixBody');
  if (!nameEl || !bodyEl) return;
  if (!nome) {
    nameEl.textContent = '';
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Clique em um cliente ao lado para ver seu mix</span></div>';
    return;
  }
  var mix = (VENDAS_DATA.mix_por_cliente || {})[nome] || [];
  nameEl.textContent = '- ' + nome;
  if (!mix.length) {
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Sem dados de mix para este cliente</span></div>';
    return;
  }
  var maxVal = mix[0].caixas || 1;
  bodyEl.innerHTML = mix.map(function(p) {
    var pct = (p.caixas / maxVal * 100).toFixed(1);
    return '<div class="mix-row">' +
      '<div class="mix-prod-name">' + p.produto + '</div>' +
      '<div class="mix-prod-cat">' + (p.categoria || '') + '</div>' +
      '<div class="mix-bar-wrap"><div class="mix-bar" style="width:' + pct + '%"></div></div>' +
      '<div class="mix-prod-vals">' +
        '<span>' + fmtNum.format(p.caixas) + ' CX</span>' +
        '<span style="color:var(--text-secondary);margin-left:8px">' + fmtNum.format(p.unidades) + ' UN</span>' +
      '</div></div>';
  }).join('');
}

function renderVendasSugeridos(nome) {
  var nameEl = document.getElementById('vendasSugeridosName');
  var bodyEl = document.getElementById('vendasSugeridosBody');
  if (!nameEl || !bodyEl) return;
  if (!nome) {
    nameEl.textContent = '';
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Selecione um cliente para ver sugestoes</span></div>';
    return;
  }
  var mix = (VENDAS_DATA.mix_por_cliente || {})[nome] || [];
  var todosProdutos = VENDAS_DATA.todos_produtos || [];
  var produtosDoCliente = {};
  var categoriasDoCliente = {};
  mix.forEach(function(p) {
    produtosDoCliente[p.produto] = true;
    if (p.categoria) categoriasDoCliente[p.categoria] = true;
  });
  var excluirKeywords = ['caixa', 'aurok', 'feed', 'weasy', 'hostzer'];
  var sugeridos = todosProdutos.filter(function(p) {
    if (produtosDoCliente[p.produto]) return false;
    if (!categoriasDoCliente[p.categoria]) return false;
    var nomeLower = p.produto.toLowerCase();
    for (var i = 0; i < excluirKeywords.length; i++) {
      if (nomeLower.indexOf(excluirKeywords[i]) !== -1) return false;
    }
    return true;
  });
  nameEl.textContent = '- ' + nome;
  if (!sugeridos.length) {
    bodyEl.innerHTML = '<div class="mix-placeholder"><span style="color:var(--text-secondary);font-size:13px">Este cliente ja compra todos os produtos disponiveis nas suas categorias</span></div>';
    return;
  }
  var categorias = {};
  sugeridos.forEach(function(p) {
    var cat = p.categoria || 'Outros';
    if (!categorias[cat]) categorias[cat] = [];
    categorias[cat].push(p.produto);
  });
  var html = '';
  Object.keys(categorias).sort().forEach(function(cat) {
    html += '<div class="sugerido-cat">' + cat + '</div>';
    categorias[cat].forEach(function(prod) {
      html += '<div class="sugerido-item">' +
        '<img class="icon" data-icon="material-symbols:add-circle-outline" alt="" style="width:16px;height:16px;color:#f59e0b">' +
        '<span>' + prod + '</span></div>';
    });
  });
  bodyEl.innerHTML = html;
  if (typeof updateAllIcons === 'function') updateAllIcons();
}

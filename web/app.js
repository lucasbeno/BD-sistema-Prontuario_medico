// ------------------------------------------------------------------ API
const api = {
    async get(url, params) {
        const qs = params ? "?" + new URLSearchParams(limpar(params)) : "";
        return tratar(await fetch(url + qs));
    },
    async enviar(metodo, url, dados) {
        return tratar(await fetch(url, {
            method: metodo,
            headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8" },
            body: new URLSearchParams(dados || {}),
        }));
    },
};

function limpar(obj) {
    return Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== null && v !== undefined && v !== ""));
}

async function tratar(resposta) {
    const corpo = await resposta.json();
    if (!resposta.ok) throw new Error(corpo.erro || "Erro " + resposta.status);
    return corpo;
}

// --------------------------------------------------------------- utilidades
const $ = id => document.getElementById(id);

function avisar(texto, falha = false) {
    const el = $("aviso");
    el.textContent = texto;
    el.classList.toggle("falha", falha);
    el.classList.add("visivel");
    clearTimeout(avisar.timer);
    avisar.timer = setTimeout(() => el.classList.remove("visivel"), 4000);
}

function escapar(valor) {
    return String(valor).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function dataBR(iso) {
    const [a, m, d] = String(iso).slice(0, 10).split("-");
    return `${d}/${m}/${a}`;
}

function formatar(valor) {
    if (valor === null || valor === undefined) return "";
    if (typeof valor === "boolean") return valor ? "1 (sim)" : "0 (não)";
    if (typeof valor === "number") return Number.isInteger(valor) ? String(valor) : valor.toLocaleString("pt-BR");
    const s = String(valor);
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return dataBR(s);
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(s)) return dataBR(s) + " " + s.slice(11, 16);
    return s;
}

function num(valor, casas = 2) {
    if (valor === null || valor === undefined) return "—";
    return Number(valor).toLocaleString("pt-BR", { maximumFractionDigits: casas });
}

function celula(valor) {
    if (valor === null || valor === undefined) return '<td class="nulo">NULL</td>';
    const cls = typeof valor === "number" ? ' class="num"' : "";
    return `<td${cls}>${escapar(formatar(valor))}</td>`;
}

/** Tabela HTML a partir de uma lista de objetos ou de {columns, rows}. */
function tabelaHTML(linhas, colunas) {
    if (!linhas.length) return '<tbody><tr><td class="vazio-linha">Nenhuma linha.</td></tr></tbody>';
    const cols = colunas || Object.keys(linhas[0]);
    return `<thead><tr>${cols.map(c => `<th>${escapar(c)}</th>`).join("")}</tr></thead>
        <tbody>${linhas.map(l => `<tr>${cols.map(c => celula(l[c])).join("")}</tr>`).join("")}</tbody>`;
}

function preencherSelect(el, opcoes, vazio) {
    el.innerHTML = (vazio !== undefined ? `<option value="">${escapar(vazio)}</option>` : "") +
        opcoes.map(([v, t]) => `<option value="${escapar(v)}">${escapar(t)}</option>`).join("");
}

// ------------------------------------------------------------------- abas
document.querySelectorAll(".menu nav button").forEach(botao => {
    botao.addEventListener("click", () => abrirAba(botao.dataset.aba));
});

function abrirAba(nome) {
    document.querySelectorAll(".menu nav button").forEach(b => b.classList.toggle("ativo", b.dataset.aba === nome));
    document.querySelectorAll(".aba").forEach(s => s.classList.toggle("ativa", s.id === "aba-" + nome));
    if (nome === "dashboard") carregarDashboard();
    else if (nome === "relatorios") carregarRelatorios();
    else if (nome === "regras") carregarRegras();
    else carregarEntidade(nome);
}

/* =====================================================================
   GRÁFICOS — paleta categórica validada (ordem fixa, nunca reciclada),
   marcas finas, grade recessiva e tooltip em todos os gráficos.
   ===================================================================== */
const SERIE = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"];
const NEUTRO = "#8a8984";
const TEXTO_2 = "#52514e";
const GRADE = "#ebeae6";
const STATUS = {
    "Regular": "#0ca30c",
    "Atenção — acompanhar": "#fab219",
    "Polifarmácia — revisar medicação": "#d03b3b",
    "Sem medicação prescrita": "#b4b3ad",
};

if (window.Chart) {
    Chart.defaults.font.family = '"Segoe UI", system-ui, -apple-system, sans-serif';
    Chart.defaults.font.size = 12;
    Chart.defaults.color = TEXTO_2;
    Chart.defaults.borderColor = GRADE;
    Chart.defaults.animation.duration = 350;
    Chart.defaults.plugins.legend.labels.boxWidth = 12;
    Chart.defaults.plugins.legend.labels.boxHeight = 12;
    Chart.defaults.plugins.tooltip.backgroundColor = "#1d2533";
    Chart.defaults.plugins.tooltip.padding = 10;
    Chart.defaults.maintainAspectRatio = false;
}

const graficos = {};

function desenhar(id, config) {
    if (graficos[id]) graficos[id].destroy();
    const canvas = $(id);
    if (!window.Chart) {
        canvas.parentElement.innerHTML = '<p class="ajuda">Chart.js não carregou (sem internet?). Os dados estão em “Dados e SQL”.</p>';
        return;
    }
    graficos[id] = new Chart(canvas, config);
    return graficos[id];
}

function eixos({ x = {}, y = {} } = {}) {
    const base = { grid: { color: GRADE, drawTicks: false }, border: { display: false }, ticks: { padding: 6 } };
    return {
        x: { ...base, ...x, ticks: { ...base.ticks, ...(x.ticks || {}) }, title: { display: !!x.titulo, text: x.titulo } },
        y: { ...base, ...y, ticks: { ...base.ticks, ...(y.ticks || {}) }, title: { display: !!y.titulo, text: y.titulo } },
    };
}

function barras(id, rotulos, series, { horizontal = false, aoClicar, tituloX, tituloY, destaque } = {}) {
    const um = series.length === 1;
    return desenhar(id, {
        type: "bar",
        data: {
            labels: rotulos,
            datasets: series.map((s, i) => ({
                label: s.nome,
                data: s.dados,
                backgroundColor: destaque
                    ? rotulos.map(r => (r === destaque ? SERIE[0] : "#a9c8ee"))
                    : (s.cor || SERIE[i]),
                borderRadius: 4,
                borderSkipped: "start",
                maxBarThickness: 26,
                categoryPercentage: 0.8,
                barPercentage: um ? 0.9 : 0.85,
            })),
        },
        options: {
            indexAxis: horizontal ? "y" : "x",
            plugins: { legend: { display: !um, position: "bottom" } },
            scales: eixos({
                x: horizontal ? { beginAtZero: true, ticks: { precision: 0 }, titulo: tituloX } : { grid: { display: false }, titulo: tituloX },
                y: horizontal ? { grid: { display: false }, ticks: { autoSkip: false } } : { beginAtZero: true, ticks: { precision: 0 }, titulo: tituloY },
            }),
            onClick: aoClicar ? (evt, elementos) => { if (elementos.length) aoClicar(rotulos[elementos[0].index]); } : undefined,
            onHover: aoClicar ? (evt, el) => { evt.native.target.style.cursor = el.length ? "pointer" : "default"; } : undefined,
        },
    });
}

function rosca(id, linhas, cores) {
    return desenhar(id, {
        type: "doughnut",
        data: {
            labels: linhas.map(l => l.rotulo),
            datasets: [{
                data: linhas.map(l => Number(l.valor)),
                backgroundColor: linhas.map((l, i) => (cores && cores[l.rotulo]) || SERIE[i] || NEUTRO),
                borderColor: "#fff",
                borderWidth: 2,
            }],
        },
        options: {
            cutout: "55%",
            plugins: {
                legend: { position: "bottom" },
                tooltip: {
                    callbacks: {
                        label: ctx => {
                            const total = ctx.dataset.data.reduce((a, b) => a + b, 0);
                            return ` ${ctx.label}: ${ctx.parsed} (${num(100 * ctx.parsed / total, 1)}%)`;
                        },
                    },
                },
            },
        },
    });
}

function alturaPorItens(canvasId, n, min = 260) {
    $(canvasId).parentElement.style.height = Math.max(min, n * 24 + 60) + "px";
}

/** Anexa ao cartão um <details> com a tabela de dados e o(s) SQL(s) executado(s). */
function detalhes(cartao, linhas, sqls) {
    let el = cartao.querySelector("details.dados-sql");
    const aberto = el ? el.open : false;
    if (el) el.remove();
    el = document.createElement("details");
    el.className = "dados-sql";
    el.open = aberto;
    el.innerHTML = `<summary>Dados e SQL</summary>
        <div class="tabela-wrap baixa"><table>${tabelaHTML(linhas)}</table></div>
        ${sqls.filter(Boolean).map(s => `<pre class="sql">${escapar(s)}</pre>`).join("")}`;
    cartao.appendChild(el);
}

/* =====================================================================
   DASHBOARD
   ===================================================================== */
let opcoesDash = null;
let dadosDash = null;
let topAtual = "topMedicamentos";

async function carregarOpcoesDashboard() {
    if (opcoesDash) return;
    opcoesDash = await api.get("/api/dashboard/opcoes");
    preencherSelect($("f-especialidade"), opcoesDash.especialidades.map(e => [e, e]), "Todas");
    $("f-convenios").innerHTML = opcoesDash.convenios
        .map(c => `<option value="${c.codigo}">${escapar(c.nome)}</option>`).join("");
    $("f-inicio").value = opcoesDash.dataMin;
    $("f-fim").value = opcoesDash.dataMax;
}

function filtrosDashboard() {
    return {
        inicio: $("f-inicio").value,
        fim: $("f-fim").value,
        especialidade: $("f-especialidade").value,
        pagamento: $("f-pagamento").value,
        tipo: $("f-tipo").value,
    };
}

["f-inicio", "f-fim", "f-especialidade", "f-pagamento", "f-tipo"].forEach(id =>
    $(id).addEventListener("change", carregarDashboard));

document.querySelectorAll("[data-periodo]").forEach(b => b.addEventListener("click", () => {
    const fim = new Date(opcoesDash.dataMax + "T00:00:00");
    const p = b.dataset.periodo;
    if (p === "tudo") {
        $("f-inicio").value = opcoesDash.dataMin;
        $("f-fim").value = opcoesDash.dataMax;
    } else if (p === "ano") {
        $("f-inicio").value = "2026-01-01";
        $("f-fim").value = "2026-12-31";
    } else {
        const ini = new Date(fim.getFullYear(), fim.getMonth() - Number(p) + 1, 1);
        $("f-inicio").value = ini.toISOString().slice(0, 10);
        $("f-fim").value = opcoesDash.dataMax;
    }
    carregarDashboard();
}));

$("f-limpar").addEventListener("click", () => {
    $("f-inicio").value = opcoesDash.dataMin;
    $("f-fim").value = opcoesDash.dataMax;
    ["f-especialidade", "f-pagamento", "f-tipo"].forEach(id => { $(id).value = ""; });
    carregarDashboard();
});

$("f-variavel").addEventListener("change", () => desenharHistograma());

document.querySelectorAll("[data-top]").forEach(b => b.addEventListener("click", () => {
    topAtual = b.dataset.top;
    document.querySelectorAll("[data-top]").forEach(x => x.classList.toggle("ativo", x === b));
    desenharTop();
}));

async function carregarDashboard() {
    try {
        await carregarOpcoesDashboard();
        const d = await api.get("/api/dashboard", filtrosDashboard());
        dadosDash = d;
        desenharResumoFiltro(d.filtro);
        desenharKpis(d);
        desenharSerie(d);
        desenharEspecialidades(d);
        rosca("g-polifarmacia", d.polifarmacia, STATUS);
        cartao("polifarmacia", d.polifarmacia, [d.sql.polifarmacia]);
        prepararVariaveis(d);
        desenharHistograma();
        desenharTop();
        desenharRadar(d);
        desenharDispersao(d);
        barras("g-semana", d.diaSemana.map(l => l.rotulo), [{ nome: "Consultas", dados: d.diaSemana.map(l => l.valor) }],
            { tituloY: "consultas" });
        cartao("diaSemana", d.diaSemana, [d.sql.diaSemana]);
        desenharTabelaEstat(d);
    } catch (e) {
        avisar(e.message, true);
    }
}

function cartao(chave, linhas, sqls) {
    detalhes(document.querySelector(`figure[data-chave="${chave}"]`), linhas, sqls);
}

function desenharResumoFiltro(f) {
    const partes = [`Período: <b>${dataBR(f.inicio)}</b> a <b>${dataBR(f.fim)}</b>`];
    if (f.especialidade) partes.push(`Especialidade: <b>${escapar(f.especialidade)}</b>`);
    if (f.pagamento) partes.push(`Pagamento: <b>${escapar($("f-pagamento").selectedOptions[0].text)}</b>`);
    if (f.tipo) partes.push(`Tipo: <b>${f.tipo === "R" ? "Retorno" : "Primeira consulta"}</b>`);
    $("filtro-resumo").innerHTML = partes.join(" · ");
}

function desenharKpis(d) {
    const k = d.indicadores;
    let variacao;
    if (k.variacao_pct === null) {
        variacao = `<em class="neutro">sem consultas no período anterior (${escapar(k.periodo_anterior.split(" a ").map(dataBR).join(" a "))})</em>`;
    } else {
        const sinal = k.variacao_pct > 0 ? "▲" : (k.variacao_pct < 0 ? "▼" : "■");
        const cls = k.variacao_pct > 0 ? "sobe" : (k.variacao_pct < 0 ? "desce" : "neutro");
        variacao = `<em class="${cls}">${sinal} ${num(Math.abs(k.variacao_pct), 1)}% vs período anterior (${k.consultas_periodo_anterior})</em>`;
    }
    const tiles = [
        ["Consultas no período", k.consultas, variacao],
        ["Pacientes atendidos", k.pacientes_atendidos, `de ${d.cadastro.pacientes} cadastrados`],
        ["Médicos com consulta", k.medicos_ativos, `de ${d.cadastro.medicos} cadastrados`],
        ["Média de consultas / mês", num(k.consultas_por_mes, 1), "no período escolhido"],
        ["% de retornos", k.consultas ? num(k.pct_retornos, 1) + "%" : "—", "consultas que são retorno"],
        ["% particulares", k.consultas ? num(k.pct_particulares, 1) + "%" : "—", "consultas sem convênio"],
        ["Medicamentos por receita", num(k.medicamentos_por_receita), "média"],
        ["Exames por consulta", num(k.exames_por_consulta), "média"],
    ];
    $("kpis").innerHTML = tiles.map(([r, v, s]) =>
        `<div class="kpi"><span>${r}</span><strong>${v}</strong><small>${s}</small></div>`).join("");
    const c = d.cadastro;
    $("cadastro").innerHTML = `No banco: <b>${c.pacientes}</b> pacientes · <b>${c.medicos}</b> médicos · <b>${c.convenios}</b> convênios ·
        <b>${c.medicamentos}</b> medicamentos · <b>${c.exames}</b> exames · <b>${c.registros_log}</b> registros em <code>log_auditoria</code>`;
}

function desenharSerie(d) {
    const s = d.serieMensal;
    const t = d.tendencia;
    const rotulos = s.map(l => { const [a, m] = l.mes.split("-"); return `${m}/${a.slice(2)}`; });
    const reta = t.inclinacao === null ? [] : s.map((l, i) => Number(t.intercepto) + Number(t.inclinacao) * (i + 1));
    desenhar("g-serie", {
        data: {
            labels: rotulos,
            datasets: [
                { type: "bar", label: "Primeira consulta", data: s.map(l => l.primeiras), backgroundColor: SERIE[0], stack: "c", borderRadius: 3, maxBarThickness: 34 },
                { type: "bar", label: "Retorno", data: s.map(l => l.retornos), backgroundColor: SERIE[1], stack: "c", borderRadius: 3, maxBarThickness: 34 },
                { type: "line", label: "Média móvel (3 meses)", stack: "media", data: s.map(l => l.media_movel_3m), borderColor: "#1d2533", backgroundColor: "#1d2533", borderWidth: 2, pointRadius: 3, tension: 0.25 },
                { type: "line", label: "Tendência linear", stack: "tendencia", data: reta, borderColor: NEUTRO, borderWidth: 1.5, borderDash: [6, 4], pointRadius: 0 },
            ],
        },
        options: {
            interaction: { mode: "index", intersect: false },
            plugins: {
                legend: { position: "bottom" },
                tooltip: { callbacks: { footer: itens => `Total: ${s[itens[0].dataIndex].total}` } },
            },
            scales: eixos({ x: { stacked: true, grid: { display: false } }, y: { stacked: true, beginAtZero: true, ticks: { precision: 0 }, titulo: "consultas" } }),
        },
    });
    $("nota-tendencia").innerHTML = t.inclinacao === null ? "" :
        `Tendência linear (mínimos quadrados sobre ${t.n} meses): <b>${t.inclinacao >= 0 ? "+" : ""}${num(t.inclinacao)}</b> consulta/mês ·
         correlação mês × consultas <b>r = ${num(t.r, 2)}</b> (${forca(t.r)}).`;
    cartao("serieMensal", s, [d.sql.serieMensal, d.sql.tendencia]);
}

function forca(r) {
    if (r === null || r === undefined) return "indefinida";
    const a = Math.abs(r);
    const f = a >= 0.7 ? "forte" : a >= 0.4 ? "moderada" : a >= 0.2 ? "fraca" : "desprezível";
    return `${f}${r > 0 ? " e positiva" : r < 0 ? " e negativa" : ""}`;
}

function desenharEspecialidades(d) {
    const l = d.porEspecialidade;
    alturaPorItens("g-especialidade", l.length);
    barras("g-especialidade", l.map(x => x.rotulo), [{ nome: "Consultas", dados: l.map(x => x.valor) }], {
        horizontal: true,
        tituloX: "consultas",
        destaque: d.filtro.especialidade || undefined,
        aoClicar: rotulo => {
            $("f-especialidade").value = $("f-especialidade").value === rotulo ? "" : rotulo;
            carregarDashboard();
        },
    });
    cartao("porEspecialidade", l, [d.sql.porEspecialidade]);
}

function prepararVariaveis(d) {
    const sel = $("f-variavel");
    const atual = sel.value;
    preencherSelect(sel, d.estatisticas.map(e => [e.id, e.rotulo]));
    if (atual) sel.value = atual;
}

function desenharHistograma() {
    const d = dadosDash;
    const e = d.estatisticas.find(x => x.id === $("f-variavel").value) || d.estatisticas[0];
    const rot = e.frequencias.map(f => e.largura === 1 ? String(f.faixa) : `${f.faixa}–${f.faixa + e.largura - 1}`);
    barras("g-histograma", rot, [{ nome: "Frequência", dados: e.frequencias.map(f => f.valor) }],
        { tituloX: e.unidade + (e.largura > 1 ? ` (faixas de ${e.largura})` : ""), tituloY: "frequência" });
    const chip = (r, v) => `<span><small>${r}</small><b>${v}</b></span>`;
    $("chips-estat").innerHTML = e.n ? [
        chip("n", e.n), chip("média", num(e.media)), chip("mediana", num(e.mediana)), chip("moda", e.moda ?? "—"),
        chip("variância", num(e.variancia, 3)), chip("desvio padrão", num(e.desvio_padrao, 3)),
        chip("coef. variação", e.coef_variacao === null ? "—" : num(e.coef_variacao, 1) + "%"),
        chip("mín–máx", `${e.minimo}–${e.maximo}`),
    ].join("") : '<span class="ajuda">Sem observações para este filtro.</span>';
    cartao("estatisticas", e.frequencias, [d.sql["estat_" + e.id], d.sql["freq_" + e.id]]);
}

function desenharTop() {
    const d = dadosDash;
    const l = d[topAtual];
    alturaPorItens("g-top", l.length);
    barras("g-top", l.map(x => x.rotulo), [{ nome: "Vezes", dados: l.map(x => x.valor) }],
        { horizontal: true, tituloX: topAtual === "topMedicamentos" ? "vezes prescrito" : "vezes solicitado" });
    cartao("top", l, [d.sql[topAtual]]);
}

function desenharRadar(d) {
    const eixosRadar = [
        ["consultas", "Consultas"], ["pacientes", "Pacientes"], ["pct_retornos", "% retornos"],
        ["medicamentos_por_consulta", "Medicamentos/consulta"], ["exames_por_consulta", "Exames/consulta"],
    ];
    const maximos = Object.fromEntries(eixosRadar.map(([c]) => [c, Math.max(...d.radar.map(r => Number(r[c])), 0)]));
    const top = d.radar.slice(0, 3);
    desenhar("g-radar", {
        type: "radar",
        data: {
            labels: eixosRadar.map(([, r]) => r),
            datasets: top.map((r, i) => ({
                label: r.especialidade,
                data: eixosRadar.map(([c]) => maximos[c] ? Math.round(100 * Number(r[c]) / maximos[c]) : 0),
                valores: eixosRadar.map(([c]) => r[c]),
                borderColor: SERIE[i],
                backgroundColor: SERIE[i] + "22",
                borderWidth: 2,
                pointRadius: 3,
                pointBackgroundColor: SERIE[i],
            })),
        },
        options: {
            plugins: {
                legend: { position: "bottom" },
                tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${num(ctx.dataset.valores[ctx.dataIndex])} (${ctx.parsed.r}% do maior)` } },
            },
            scales: { r: { min: 0, max: 100, ticks: { stepSize: 25, display: false }, grid: { color: GRADE }, angleLines: { color: GRADE }, pointLabels: { font: { size: 12 } } } },
        },
    });
    cartao("radar", d.radar, [d.sql.radar]);
}

function desenharDispersao(d) {
    const disp = d.dispersao;
    const pts = disp.pontos;
    const maxP = Math.max(...pts.map(p => p.pacientes), 1);
    const xs = pts.map(p => p.x);
    const xmin = Math.min(...xs), xmax = Math.max(...xs);
    const reta = disp.inclinacao === null ? [] : [xmin, xmax].map(x => ({ x, y: Number(disp.intercepto) + Number(disp.inclinacao) * x }));
    desenhar("g-dispersao", {
        type: "bubble",
        data: {
            datasets: [
                {
                    label: "Pacientes (tamanho = quantidade)",
                    data: pts.map(p => ({ x: p.x, y: p.y, r: 5 + 13 * Math.sqrt(p.pacientes / maxP), n: p.pacientes })),
                    backgroundColor: SERIE[0] + "99",
                    borderColor: "#fff",
                    borderWidth: 2,
                },
                { type: "line", label: "Reta de mínimos quadrados", data: reta, borderColor: SERIE[1], borderWidth: 2, pointRadius: 0 },
            ],
        },
        options: {
            plugins: {
                legend: { position: "bottom" },
                tooltip: { callbacks: { label: ctx => ctx.dataset.type === "line" ? " reta de tendência"
                    : ` ${ctx.raw.n} paciente(s): ${ctx.raw.x} consulta(s), ${ctx.raw.y} medicamento(s) distinto(s)` } },
            },
            scales: eixos({
                x: { type: "linear", min: Math.max(0, xmin - 1), max: xmax + 1, ticks: { stepSize: 1 }, titulo: "consultas do paciente" },
                y: { min: 0, ticks: { stepSize: 1 }, titulo: "medicamentos distintos" },
            }),
        },
    });
    $("nota-correlacao").innerHTML = disp.r === null ? "Correlação indefinida para este filtro (pouca variação)." :
        `Pearson <b>r = ${num(disp.r, 2)}</b> (${forca(disp.r)}) · reta: <b>y = ${num(disp.intercepto)} + ${num(disp.inclinacao)}·x</b> · n = ${disp.n} pacientes`;
    cartao("dispersao", pts, [d.sql.dispersao, d.sql.correlacao]);
}

function desenharTabelaEstat(d) {
    const cols = ["Variável", "n", "Média", "Mediana", "Moda", "Variância", "Desvio padrão", "CV", "Mín", "Máx"];
    $("tabela-estat").innerHTML = `<thead><tr>${cols.map(c => `<th>${c}</th>`).join("")}</tr></thead><tbody>` +
        d.estatisticas.map(e => `<tr><td>${escapar(e.rotulo)}</td><td class="num">${e.n}</td>
            <td class="num">${num(e.media)}</td><td class="num">${num(e.mediana)}</td><td class="num">${e.moda ?? "—"}</td>
            <td class="num">${num(e.variancia, 3)}</td><td class="num">${num(e.desvio_padrao, 3)}</td>
            <td class="num">${e.coef_variacao === null ? "—" : num(e.coef_variacao, 1) + "%"}</td>
            <td class="num">${e.minimo ?? "—"}</td><td class="num">${e.maximo ?? "—"}</td></tr>`).join("") + "</tbody>";
    const primeira = d.estatisticas[0];
    cartao("estatisticas-tabela", d.estatisticas.map(({ frequencias, ...resto }) => resto),
        [d.sql["estat_" + primeira.id].replace(/^/, "-- exemplo (" + primeira.rotulo + "); as outras variáveis só trocam a CTE v\n")]);
}

/* =====================================================================
   CONSULTAS E VISÕES (Etapas 03 e 04)
   ===================================================================== */
let relatorios = null;

async function carregarRelatorios() {
    if (relatorios) return;
    try {
        relatorios = await api.get("/api/relatorios");
        const grupos = {};
        relatorios.forEach(r => (grupos[r.etapa] = grupos[r.etapa] || []).push(r));
        $("lista-relatorios").innerHTML = Object.entries(grupos).map(([etapa, lista]) =>
            `<h3 class="grupo-rel">${escapar(etapa)}</h3><ol>${lista.map(r =>
                `<li><button data-id="${r.id}"><strong>${escapar(r.titulo)}</strong><small>${escapar(r.tecnica)}</small></button></li>`).join("")}</ol>`).join("");
        $("lista-relatorios").querySelectorAll("button").forEach(b => b.addEventListener("click", () => abrirRelatorio(b.dataset.id)));
        abrirRelatorio(relatorios[0].id);
    } catch (e) {
        avisar(e.message, true);
    }
}

function abrirRelatorio(id) {
    document.querySelectorAll("#lista-relatorios button").forEach(b => b.classList.toggle("ativo", b.dataset.id === id));
    const r = relatorios.find(x => x.id === id);
    const alvo = $("resultado-relatorio");
    alvo.classList.remove("vazio");
    const campos = r.filtros.map(f => {
        const nome = `name="${f.nome}"`;
        let entrada;
        if (f.tipo === "opcao") {
            entrada = `<select ${nome}><option value="">Todos</option>${f.opcoes.map(o => `<option>${escapar(o)}</option>`).join("")}</select>`;
        } else if (f.tipo === "de" || f.tipo === "ate") {
            entrada = `<input type="date" ${nome}>`;
        } else if (f.tipo === "min" || f.tipo === "limite") {
            entrada = `<input type="number" min="0" ${nome} value="${f.padrao ?? ""}" style="width:90px">`;
        } else {
            entrada = `<input type="text" ${nome} placeholder="digite...">`;
        }
        return `<label>${escapar(f.rotulo)} ${entrada}</label>`;
    }).join("");
    alvo.innerHTML = `
        <div class="rel-cab">
            <span class="tag">${escapar(r.etapa)}</span>
            <h2>${escapar(r.titulo)}</h2>
            <p class="pergunta">${escapar(r.pergunta)}</p>
            <p class="ajuda">Técnica: ${escapar(r.tecnica)}</p>
        </div>
        <form class="linha-form filtros-rel" id="form-rel">${campos}
            ${r.filtros.length ? '<button type="button" class="btn" id="rel-limpar">Limpar</button>' : '<span class="ajuda">Esta consulta não tem parâmetros.</span>'}
        </form>
        <div class="kpis pequenos" id="rel-kpis"></div>
        ${r.grafico ? `<figure class="cartao-interno"><figcaption>${escapar(r.grafico.titulo)}</figcaption><div class="canvas"><canvas id="g-relatorio"></canvas></div></figure>` : ""}
        <p class="contagem" id="rel-contagem"></p>
        <div class="tabela-wrap baixa"><table id="rel-tabela"></table></div>
        <details class="dados-sql"><summary>Ver SQL</summary><pre class="sql" id="rel-sql-exec"></pre></details>`;
    const form = $("form-rel");
    form.addEventListener("input", () => { clearTimeout(form.t); form.t = setTimeout(() => executarRelatorio(r), 300); });
    form.addEventListener("submit", ev => { ev.preventDefault(); executarRelatorio(r); });
    const limparBtn = $("rel-limpar");
    if (limparBtn) limparBtn.addEventListener("click", () => { form.reset(); executarRelatorio(r); });
    executarRelatorio(r);
}

async function executarRelatorio(r) {
    try {
        const params = Object.fromEntries(new FormData($("form-rel")));
        const res = await api.get("/api/relatorios/" + r.id, params);
        const linhas = res.rows.map(l => Object.fromEntries(res.columns.map((c, i) => [c, l[i]])));
        $("rel-contagem").textContent = `${linhas.length} linha(s) retornada(s)`;
        $("rel-tabela").innerHTML = tabelaHTML(linhas, res.columns);
        $("rel-sql-exec").textContent = res.sqlExecutado;
        $("rel-kpis").innerHTML = r.indicadores.map(ind =>
            `<div class="kpi"><span>${escapar(ind.rotulo)}</span><strong>${indicador(ind, linhas)}</strong></div>`).join("");
        if (r.grafico) graficoRelatorio(r.grafico, linhas);
    } catch (e) {
        avisar(e.message, true);
    }
}

function indicador(ind, linhas) {
    const vals = ind.coluna ? linhas.map(l => l[ind.coluna]).filter(v => v !== null && v !== undefined) : [];
    switch (ind.tipo) {
        case "linhas": return linhas.length;
        case "soma": return num(vals.reduce((a, b) => a + Number(b), 0));
        case "media": return vals.length ? num(vals.reduce((a, b) => a + Number(b), 0) / vals.length) : "—";
        case "max": return vals.length ? num(Math.max(...vals.map(Number))) : "—";
        case "primeiro": return vals.length ? num(vals[0]) : "—";
        case "distintos": return new Set(vals).size;
        default: return "—";
    }
}

function graficoRelatorio(g, linhas) {
    let rotulos, series;
    if (g.agrupar) {
        const cont = new Map();
        linhas.forEach(l => { const k = l[g.agrupar] ?? "(vazio)"; cont.set(k, (cont.get(k) || 0) + 1); });
        let pares = [...cont.entries()];
        const numericos = pares.every(([k]) => typeof k === "number");
        pares.sort((a, b) => numericos ? a[0] - b[0] : b[1] - a[1] || String(a[0]).localeCompare(String(b[0])));
        if (g.tipo === "rosca" && pares.length > 6) {
            const resto = pares.slice(5).reduce((s, [, v]) => s + v, 0);
            pares = [...pares.slice(0, 5), ["Outros", resto]];
        }
        rotulos = pares.map(([k]) => String(k));
        series = [{ nome: "Linhas", dados: pares.map(([, v]) => v) }];
    } else {
        rotulos = linhas.map(l => String(l[g.rotulo]));
        series = g.valores.map(v => ({ nome: v.replaceAll("_", " "), dados: linhas.map(l => Number(l[v])) }));
    }
    if (g.tipo === "rosca") {
        rosca("g-relatorio", rotulos.map((r, i) => ({ rotulo: r, valor: series[0].dados[i] })));
        $("g-relatorio").parentElement.style.height = "300px";
        return;
    }
    const horizontal = g.tipo === "barra-h";
    if (horizontal) alturaPorItens("g-relatorio", rotulos.length * (series.length > 1 ? 1.6 : 1));
    else $("g-relatorio").parentElement.style.height = "300px";
    barras("g-relatorio", rotulos, series, { horizontal });
}

/* =====================================================================
   ETAPA 05 — FUNÇÕES, PROCEDIMENTOS E TRIGGERS
   ===================================================================== */
let regrasProntas = false;

async function carregarRegras() {
    try {
        if (!regrasProntas) {
            const [pacientes, medicamentos, convenios, consultas] = await Promise.all([
                api.get("/api/pacientes"), api.get("/api/medicamentos"), api.get("/api/convenios"),
                api.get("/api/regras/consultas-com-receita"),
            ]);
            const opPac = pacientes.map(p => [p.cpf, `${p.nome} (${p.numero_prontuario})`]);
            const opMed = medicamentos.map(m => [m.codigo, `${m.nome} (cód. ${m.codigo})`]);
            preencherSelect($("r-paciente"), opPac);
            preencherSelect($("r-paciente-conv"), pacientes.map(p => [p.cpf, `${p.nome} — atual: ${p.convenio}`]));
            preencherSelect($("r-medicamento"), opMed);
            preencherSelect($("r-medicamento-trig"), opMed);
            preencherSelect($("r-convenio"), convenios.map(c => [c.codigo, c.nome]), "Particular (NULL)");
            preencherSelect($("r-consulta-trig"), consultas.map(c =>
                [c.codigo, `nº ${c.codigo} — ${c.paciente}${c.alergias ? " · alergias: " + c.alergias : ""}`]));
            // exemplos prontos para a apresentação
            $("r-paciente").value = "10000000016";
            $("r-medicamento").value = "29";
            $("r-paciente-conv").value = "10000000005";
            $("r-consulta-trig").value = "61";
            $("r-medicamento-trig").value = "2";
            regrasProntas = true;
        }
        carregarPolifarmacia();
        carregarConflitos();
        carregarSemConsulta();
        carregarLog();
        carregarObjetos();
    } catch (e) {
        avisar(e.message, true);
    }
}

$("r-classe").addEventListener("change", carregarPolifarmacia);

async function carregarPolifarmacia() {
    const r = await api.get("/api/regras/polifarmacia", { classe: $("r-classe").value });
    rosca("g-r-polifarmacia", r.resumo, STATUS);
    $("r-tabela-polifarmacia").innerHTML = tabelaHTML(r.pacientes.map(p => ({
        prontuario: p.prontuario, paciente: p.paciente, "medic. distintos": p.medicamentos_distintos, "classificação (função)": p.classificacao,
    })));
}

async function carregarConflitos() {
    const r = await api.get("/api/regras/conflitos");
    $("r-tabela-conflitos").innerHTML = r.linhas.length
        ? tabelaHTML(r.linhas, ["consulta", "data", "paciente", "medicamento", "alergias_do_paciente"])
        : '<tbody><tr><td class="vazio-linha">✓ Nenhum item de receita gravado conflita com as alergias registradas (a função devolveu 0 para todos).</td></tr></tbody>';
}

async function carregarSemConsulta() {
    $("r-tabela-sem-consulta").innerHTML = tabelaHTML(await api.get("/api/regras/sem-consulta"), ["prontuario", "paciente", "convenio"]);
}

async function carregarLog() {
    $("r-tabela-log").innerHTML = tabelaHTML(await api.get("/api/regras/log"));
}

async function carregarObjetos() {
    if ($("r-objetos").children.length) return;
    const objs = await api.get("/api/regras/objetos");
    $("r-objetos").innerHTML = objs.map(o => `<details class="dados-sql"><summary>${escapar(o.nome)}</summary>
        <pre class="sql">${escapar(o.definicao || "(sem permissão para ver o código)")}</pre></details>`).join("");
}

function caixa(ok, html) {
    return `<div class="resultado ${ok ? "ok" : "alerta"}">${html}</div>`;
}

$("r-verificar").addEventListener("click", async () => {
    try {
        const r = await api.get("/api/regras/alergia", { cpf: $("r-paciente").value, medicamento: $("r-medicamento").value });
        $("r-resultado-alergia").innerHTML = caixa(!r.conflito,
            `<b>${r.conflito ? "⚠ Conflito (função devolveu 1)" : "✓ Sem conflito (função devolveu 0)"}</b>
             <p>${escapar(r.paciente)} × ${escapar(r.medicamento)} — alergias registradas: ${escapar(r.alergias || "nenhuma")}</p>
             <pre class="sql">${escapar(r.sql)}</pre>`);
    } catch (e) { avisar(e.message, true); }
});

$("r-trocar").addEventListener("click", async () => {
    try {
        const r = await api.enviar("POST", "/api/regras/convenio", { cpf: $("r-paciente-conv").value, codigo_convenio: $("r-convenio").value });
        const c = r.cadastro;
        $("r-resultado-convenio").innerHTML = caixa(true,
            `<b>✓ Procedimento executado</b>
             <p>Prontuário ${c.prontuario} — ${escapar(c.paciente)} agora é <b>${escapar(c.convenio_atual)}</b>.</p>
             ${r.log.length ? `<p>Trigger gravou no log: <i>${escapar(r.log[0].detalhe)}</i></p>` : ""}
             <pre class="sql">${escapar(r.sql)}</pre>`);
        carregarLog();
        regrasProntas = false; // atualiza o "atual: ..." dos selects
        const sel = [$("r-paciente-conv").value, $("r-convenio").value];
        await carregarRegras();
        [$("r-paciente-conv").value, $("r-convenio").value] = sel;
    } catch (e) {
        $("r-resultado-convenio").innerHTML = caixa(false, `<b>✗ O procedimento recusou:</b> ${escapar(e.message)}`);
    }
});

async function agendar(confirmar) {
    if (confirmar && !confirm("Isto grava consultas novas de verdade (COMMIT). Continuar?")) return;
    try {
        const r = await api.enviar("POST", "/api/regras/agendar", { confirmar });
        $("r-resultado-agenda").innerHTML = caixa(true,
            `<b>${confirmar ? "✓ COMMIT" : "↺ Simulação (ROLLBACK)"} — OUT p_total_agendadas = ${r.total}</b>
             ${r.consultas.length ? `<div class="tabela-wrap baixa"><table>${tabelaHTML(r.consultas)}</table></div>` : "<p>Nenhum paciente sem consulta.</p>"}
             <pre class="sql">${escapar(r.sql)}</pre>`);
        if (confirmar) { carregarSemConsulta(); avisar(`${r.total} consulta(s) agendada(s)`); }
    } catch (e) { avisar(e.message, true); }
}
$("r-simular").addEventListener("click", () => agendar(false));
$("r-agendar").addEventListener("click", () => agendar(true));

$("r-testar-trig").addEventListener("click", async () => {
    try {
        const r = await api.enviar("POST", "/api/regras/testar-trigger",
            { codigo_consulta: $("r-consulta-trig").value, codigo_medicamento: $("r-medicamento-trig").value });
        $("r-resultado-trigger").innerHTML = caixa(!r.bloqueado,
            `<b>${r.bloqueado ? "⛔ Bloqueado pelo trigger (SQLSTATE 45000)" : "✓ Aceito"}</b><p>${escapar(r.mensagem)}</p>
             <pre class="sql">${escapar(r.sql)}</pre>`);
    } catch (e) { avisar(e.message, true); }
});

/* =====================================================================
   CRUD — 6 cadastros (pacientes, médicos, consultas, convênios,
   medicamentos, exames) + alergias e receita/exames da consulta
   ===================================================================== */
const hoje = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);

const FONTES = {
    convenio: async () => (await api.get("/api/convenios")).map(c => [c.codigo, c.nome]),
    paciente: async () => (await api.get("/api/pacientes")).map(p => [p.cpf, `${p.nome} (prontuário ${p.numero_prontuario})`]),
    medico: async () => (await api.get("/api/medicos")).map(m => [m.cpf, `${m.nome} — ${m.especialidade}`]),
    consulta: async () => (await api.get("/api/consultas/opcoes")).map(c => [c.codigo, `nº ${c.codigo} — ${c.paciente} (${dataBR(c.data_consulta)})`]),
};

const ENTIDADES = {
    pacientes: {
        singular: "paciente",
        chave: "cpf",
        colunas: [
            ["numero_prontuario", "Prontuário"], ["cpf", "CPF"], ["nome", "Nome"], ["cep", "CEP"],
            ["numero_apto", "Nº/Apto"], ["convenio", "Convênio"], ["telefones", "Telefones"],
        ],
        campos: [
            { nome: "cpf", rotulo: "CPF", dica: "11 dígitos, só números", obrigatorio: true, padrao: "[0-9]{11}" },
            { nome: "nome", rotulo: "Nome completo", obrigatorio: true },
            { nome: "cep", rotulo: "CEP", dica: "8 dígitos, só números", obrigatorio: true, padrao: "[0-9]{8}" },
            { nome: "numero_apto", rotulo: "Número / apartamento", dica: "vazio = DEFAULT 'S/N'" },
            { nome: "codigo_convenio", rotulo: "Convênio", tipo: "select", fonte: "convenio", vazio: "Particular (sem convênio)", dica: "trocar o convênio gera registro em log_auditoria (trigger)" },
            { nome: "telefone", rotulo: "Telefone", dica: "10 ou 11 dígitos com DDD", padrao: "[0-9]{10,11}", soNoCadastro: true },
        ],
        extras: [["Alergias", registro => abrirAlergias(registro)]],
    },
    medicos: {
        singular: "médico",
        chave: "cpf",
        colunas: [
            ["cpf", "CPF"], ["nome", "Nome"], ["crm", "CRM"], ["especialidade", "Especialidade"],
            ["cep", "CEP"], ["numero_apto", "Nº/Apto"], ["total_consultas", "Consultas"],
        ],
        campos: [
            { nome: "cpf", rotulo: "CPF", dica: "11 dígitos, só números", obrigatorio: true, padrao: "[0-9]{11}" },
            { nome: "nome", rotulo: "Nome completo", obrigatorio: true },
            { nome: "crm", rotulo: "CRM", dica: "formato 12345/PE", obrigatorio: true, padrao: "[0-9]{4,6}/[A-Z]{2}" },
            { nome: "especialidade", rotulo: "Especialidade", dica: "vazio = DEFAULT 'Clínica Geral'" },
            { nome: "cep", rotulo: "CEP", dica: "8 dígitos, só números", obrigatorio: true, padrao: "[0-9]{8}" },
            { nome: "numero_apto", rotulo: "Número / apartamento", dica: "vazio = DEFAULT 'S/N'" },
        ],
    },
    consultas: {
        singular: "consulta",
        chave: "codigo",
        colunas: [
            ["codigo", "Nº"], ["data_consulta", "Data"], ["tipo", "Tipo"], ["retorno_de", "Retorno de"],
            ["paciente", "Paciente"], ["medico", "Médico"], ["especialidade", "Especialidade"],
            ["numero_receita", "Receita"], ["medicamentos", "Medic."], ["exames", "Exames"],
        ],
        campos: [
            { nome: "cpf_paciente", rotulo: "Paciente", tipo: "select", fonte: "paciente", obrigatorio: true },
            { nome: "cpf_medico", rotulo: "Médico", tipo: "select", fonte: "medico", obrigatorio: true, dica: "paciente e médico iguais são recusados pelo trigger trg_consulta_pessoas" },
            { nome: "data_consulta", rotulo: "Data", tipo: "date", obrigatorio: true, padraoNovo: hoje },
            { nome: "retorno_de", rotulo: "É retorno da consulta", tipo: "select", fonte: "consulta", vazio: "Não (primeira consulta)", soNoCadastro: true },
            { nome: "nome_receita", rotulo: "Nome da receita", dica: "preencha para já criar a receita (prescricao); vazio = sem receita", soNoCadastro: true },
        ],
        extras: [["Receita e exames", registro => abrirConsulta(registro.codigo)]],
        params: () => ({ inicio: $("c-inicio").value, fim: $("c-fim").value }),
    },
    convenios: {
        singular: "convênio",
        chave: "codigo",
        colunas: [["codigo", "Código"], ["nome", "Nome"], ["total_pacientes", "Pacientes"]],
        campos: [
            { nome: "codigo", rotulo: "Código", tipo: "number", obrigatorio: true, soNaEdicao: true },
            { nome: "nome", rotulo: "Nome do plano", obrigatorio: true },
        ],
    },
    medicamentos: {
        singular: "medicamento",
        chave: "codigo",
        colunas: [["codigo", "Código"], ["nome", "Nome"], ["vezes_usado", "Vezes prescrito"]],
        campos: [
            { nome: "codigo", rotulo: "Código", tipo: "number", obrigatorio: true, soNaEdicao: true, dica: "mudar o código propaga para as receitas (ON UPDATE CASCADE)" },
            { nome: "nome", rotulo: "Nome e dose", obrigatorio: true, dica: "ex.: Paracetamol 750mg (único)" },
        ],
    },
    exames: {
        singular: "exame",
        chave: "codigo",
        colunas: [["codigo", "Código"], ["nome", "Nome"], ["vezes_usado", "Vezes solicitado"]],
        campos: [
            { nome: "codigo", rotulo: "Código", tipo: "number", obrigatorio: true, soNaEdicao: true },
            { nome: "nome", rotulo: "Nome do exame", obrigatorio: true },
        ],
    },
};

const dados = {};

async function carregarEntidade(nome) {
    try {
        const cfg = ENTIDADES[nome];
        dados[nome] = await api.get("/api/" + nome, cfg.params ? cfg.params() : undefined);
        desenharTabela(nome);
    } catch (e) {
        avisar(e.message, true);
    }
}

["c-inicio", "c-fim"].forEach(id => $(id).addEventListener("change", () => carregarEntidade("consultas")));

function desenharTabela(nome) {
    const cfg = ENTIDADES[nome];
    const filtro = document.querySelector(`[data-busca="${nome}"]`).value.toLowerCase();
    const linhas = (dados[nome] || []).filter(l =>
        !filtro || Object.values(l).some(v => v !== null && formatar(v).toLowerCase().includes(filtro)));

    const cabecalho = cfg.colunas.map(([, titulo]) => `<th>${titulo}</th>`).join("") + "<th></th>";
    const corpo = linhas.map(l => `<tr>${cfg.colunas.map(([c]) => celula(l[c])).join("")}
        <td class="acoes-linha"><div>
            ${(cfg.extras || []).map(([rotulo], i) => `<button class="btn pequeno" data-extra="${i}" data-chave="${escapar(l[cfg.chave])}">${rotulo}</button>`).join("")}
            <button class="btn pequeno" data-editar="${escapar(l[cfg.chave])}">Editar</button>
            <button class="btn pequeno perigo" data-excluir="${escapar(l[cfg.chave])}">Excluir</button>
        </div></td></tr>`).join("");
    const tabela = $("tabela-" + nome);
    tabela.innerHTML = `<thead><tr>${cabecalho}</tr></thead><tbody>${corpo}</tbody>`;

    const achar = chave => dados[nome].find(l => String(l[cfg.chave]) === chave);
    tabela.querySelectorAll("[data-editar]").forEach(b => b.addEventListener("click", () => abrirFormulario(nome, achar(b.dataset.editar))));
    tabela.querySelectorAll("[data-excluir]").forEach(b => b.addEventListener("click", () => excluir(nome, b.dataset.excluir)));
    tabela.querySelectorAll("[data-extra]").forEach(b => b.addEventListener("click", () => cfg.extras[b.dataset.extra][1](achar(b.dataset.chave))));
}

document.querySelectorAll("[data-busca]").forEach(i => i.addEventListener("input", () => desenharTabela(i.dataset.busca)));
document.querySelectorAll("[data-novo]").forEach(b => b.addEventListener("click", () => abrirFormulario(b.dataset.novo, null)));

async function excluir(nome, chave) {
    const cfg = ENTIDADES[nome];
    if (!confirm(`Excluir ${cfg.singular} ${chave}?`)) return;
    try {
        const r = await api.enviar("DELETE", `/api/${nome}/${encodeURIComponent(chave)}`);
        avisar(r.mensagem);
        carregarEntidade(nome);
    } catch (e) {
        avisar(e.message, true);
    }
}

const modal = $("modal");
const formulario = $("formulario");
let edicao = null;

$("modal-cancelar").addEventListener("click", () => modal.close());

async function abrirFormulario(nome, registro) {
    const cfg = ENTIDADES[nome];
    edicao = { nome, chave: registro ? registro[cfg.chave] : null };
    $("modal-titulo").textContent = (registro ? "Editar " : "Novo(a) ") + cfg.singular;
    $("modal-erro").textContent = "";

    const campos = cfg.campos.filter(c => registro ? !c.soNoCadastro : !c.soNaEdicao);
    const opcoes = {};
    await Promise.all(campos.filter(c => c.fonte).map(async c => { opcoes[c.nome] = await FONTES[c.fonte](); }));

    $("modal-campos").innerHTML = campos.map(c => {
        let valor = registro && registro[c.nome] !== null && registro[c.nome] !== undefined ? registro[c.nome] : "";
        if (!registro && c.padraoNovo) valor = c.padraoNovo();
        const atributos = `name="${c.nome}" id="f-${c.nome}" ${c.obrigatorio ? "required" : ""} ${c.padrao ? `pattern="${c.padrao}"` : ""}`;
        let entrada;
        if (c.tipo === "select") {
            entrada = `<select ${atributos}>${c.vazio !== undefined ? `<option value="">${escapar(c.vazio)}</option>` : (registro ? "" : '<option value="">Selecione...</option>')}` +
                opcoes[c.nome].map(([v, t]) => `<option value="${escapar(v)}" ${String(v) === String(valor) ? "selected" : ""}>${escapar(t)}</option>`).join("") +
                "</select>";
        } else {
            entrada = `<input type="${c.tipo || "text"}" ${atributos} value="${escapar(valor)}">`;
        }
        return `<div class="campo"><label for="f-${c.nome}">${c.rotulo}</label>${entrada}${c.dica ? `<small>${c.dica}</small>` : ""}</div>`;
    }).join("");

    modal.showModal();
}

formulario.addEventListener("submit", async evento => {
    evento.preventDefault();
    const valores = Object.fromEntries(new FormData(formulario));
    const { nome, chave } = edicao;
    try {
        const r = chave === null
            ? await api.enviar("POST", `/api/${nome}`, valores)
            : await api.enviar("PUT", `/api/${nome}/${encodeURIComponent(chave)}`, valores);
        modal.close();
        avisar(r.mensagem);
        carregarEntidade(nome);
    } catch (e) {
        $("modal-erro").textContent = e.message;
    }
});

// --------------------------------------------- painel lateral (alergias / consulta)
const painel = $("painel");
$("painel-fechar").addEventListener("click", () => painel.close());

function abrirPainel(titulo) {
    $("painel-titulo").textContent = titulo;
    $("painel-erro").textContent = "";
    if (!painel.open) painel.showModal();
}

async function acaoPainel(promessa, depois) {
    $("painel-erro").textContent = "";
    try {
        const r = await promessa;
        if (r && r.mensagem) avisar(r.mensagem);
        await depois();
    } catch (e) {
        $("painel-erro").textContent = e.message;
    }
}

async function abrirAlergias(paciente) {
    abrirPainel(`Alergias — ${paciente.nome}`);
    const lista = await api.get(`/api/pacientes/${paciente.cpf}/alergias`);
    const url = `/api/pacientes/${paciente.cpf}/alergias`;
    $("painel-corpo").innerHTML = `
        <p class="ajuda">Uma alergia cadastrada aqui passa a bloquear a prescrição do medicamento correspondente.</p>
        <ul class="itens">${lista.map(a => `<li>${escapar(a.alergia)} <button class="btn pequeno perigo" data-rem="${escapar(a.alergia)}">Remover</button></li>`).join("") || "<li class='ajuda'>Nenhuma alergia.</li>"}</ul>
        <div class="linha-form"><input id="nova-alergia" placeholder="ex.: Paracetamol, Penicilina..."><button class="primario" id="add-alergia">Adicionar</button></div>`;
    const recarregar = () => abrirAlergias(paciente);
    $("add-alergia").addEventListener("click", () => acaoPainel(api.enviar("POST", url, { alergia: $("nova-alergia").value }), recarregar));
    $("painel-corpo").querySelectorAll("[data-rem]").forEach(b => b.addEventListener("click", () =>
        acaoPainel(api.enviar("DELETE", `${url}/${encodeURIComponent(b.dataset.rem)}`), recarregar)));
}

async function abrirConsulta(codigo) {
    const [c, medicamentos, exames] = await Promise.all([
        api.get(`/api/consultas/${codigo}`), api.get("/api/medicamentos"), api.get("/api/exames"),
    ]);
    abrirPainel(`Consulta nº ${c.codigo} — ${dataBR(c.data_consulta)}`);
    const url = `/api/consultas/${codigo}`;
    const recarregar = async () => { await abrirConsulta(codigo); carregarEntidade("consultas"); };
    const usados = new Set(c.medicamentos.map(m => m.codigo));
    const pedidos = new Set(c.exames.map(e => e.codigo));
    $("painel-corpo").innerHTML = `
        <div class="ficha">
            <div><small>Paciente</small><b>${escapar(c.paciente)}</b></div>
            <div><small>Médico</small><b>${escapar(c.medico)}</b><span>${escapar(c.especialidade)}</span></div>
            <div><small>Tipo</small><b>${c.retorno_de ? "Retorno da nº " + c.retorno_de : "Primeira consulta"}</b></div>
        </div>
        <p class="alergias">Alergias do paciente: ${c.alergias.length ? c.alergias.map(a => `<span class="selo">${escapar(a.alergia)}</span>`).join(" ") : "nenhuma registrada"}</p>
        <h3>Receita (prescricao + contem)</h3>
        ${c.numero_receita === null ? `
            <p class="ajuda">Esta consulta ainda não tem receita.</p>
            <div class="linha-form"><input id="nome-receita" placeholder="Nome da receita (vazio = DEFAULT 'Receita padrão')"><button class="primario" id="criar-receita">Criar receita</button></div>` : `
            <p>Receita nº <b>${c.numero_receita}</b> — ${escapar(c.nome_receita || "")}
               <button class="btn pequeno perigo" id="excluir-receita">Excluir receita</button></p>
            <ul class="itens">${c.medicamentos.map(m => `<li>${escapar(m.nome)} <button class="btn pequeno perigo" data-rem-med="${m.codigo}">Remover</button></li>`).join("") || "<li class='ajuda'>Nenhum medicamento.</li>"}</ul>
            <div class="linha-form">
                <select id="sel-med">${medicamentos.filter(m => !usados.has(m.codigo)).map(m => `<option value="${m.codigo}">${escapar(m.nome)}</option>`).join("")}</select>
                <button class="primario" id="add-med">Prescrever</button>
            </div>`}
        <h3>Exames solicitados (solicita)</h3>
        <ul class="itens">${c.exames.map(e => `<li>${escapar(e.nome)} <button class="btn pequeno perigo" data-rem-ex="${e.codigo}">Remover</button></li>`).join("") || "<li class='ajuda'>Nenhum exame.</li>"}</ul>
        <div class="linha-form">
            <select id="sel-ex">${exames.filter(e => !pedidos.has(e.codigo)).map(e => `<option value="${e.codigo}">${escapar(e.nome)}</option>`).join("")}</select>
            <button class="primario" id="add-ex">Solicitar</button>
        </div>`;
    const on = (id, fn) => { const el = $(id); if (el) el.addEventListener("click", fn); };
    on("criar-receita", () => acaoPainel(api.enviar("POST", url + "/receita", { nome: $("nome-receita").value }), recarregar));
    on("excluir-receita", () => confirm("Excluir a receita e todos os itens?") && acaoPainel(api.enviar("DELETE", url + "/receita"), recarregar));
    on("add-med", () => acaoPainel(api.enviar("POST", url + "/medicamentos", { codigo_medicamento: $("sel-med").value }), recarregar));
    on("add-ex", () => acaoPainel(api.enviar("POST", url + "/exames", { codigo_exame: $("sel-ex").value }), recarregar));
    $("painel-corpo").querySelectorAll("[data-rem-med]").forEach(b => b.addEventListener("click", () =>
        acaoPainel(api.enviar("DELETE", `${url}/medicamentos/${b.dataset.remMed}`), recarregar)));
    $("painel-corpo").querySelectorAll("[data-rem-ex]").forEach(b => b.addEventListener("click", () =>
        acaoPainel(api.enviar("DELETE", `${url}/exames/${b.dataset.remEx}`), recarregar)));
}

carregarDashboard();

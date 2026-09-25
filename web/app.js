const api = {
    async get(url) {
        return tratar(await fetch(url));
    },
    async enviar(metodo, url, dados) {
        return tratar(await fetch(url, {
            method: metodo,
            headers: { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8" },
            body: new URLSearchParams(dados || {}),
        }));
    },
};

async function tratar(resposta) {
    const corpo = await resposta.json();
    if (!resposta.ok) throw new Error(corpo.erro || "Erro " + resposta.status);
    return corpo;
}

document.querySelectorAll(".menu nav button").forEach(botao => {
    botao.addEventListener("click", () => abrirAba(botao.dataset.aba));
});

function abrirAba(nome) {
    document.querySelectorAll(".menu nav button").forEach(b => b.classList.toggle("ativo", b.dataset.aba === nome));
    document.querySelectorAll(".aba").forEach(s => s.classList.toggle("ativa", s.id === "aba-" + nome));
    if (nome === "dashboard") carregarDashboard();
    else if (nome === "relatorios") carregarRelatorios();
    else carregarEntidade(nome);
}

function avisar(texto, falha = false) {
    const el = document.getElementById("aviso");
    el.textContent = texto;
    el.classList.toggle("falha", falha);
    el.classList.add("visivel");
    clearTimeout(avisar.timer);
    avisar.timer = setTimeout(() => el.classList.remove("visivel"), 3500);
}

function escapar(valor) {
    return String(valor).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function celula(valor) {
    if (valor === null || valor === undefined) return '<td class="nulo">NULL</td>';
    return typeof valor === "number" ? `<td class="num">${valor}</td>` : `<td>${escapar(valor)}</td>`;
}

const graficos = {};
const COR = "#0f766e";
const PALETA = ["#0f766e", "#f59e0b", "#6366f1", "#e11d48", "#0ea5e9", "#84cc16"];

async function carregarDashboard() {
    try {
        const d = await api.get("/api/dashboard");
        const k = d.indicadores;
        document.getElementById("kpis").innerHTML = [
            ["Pacientes", k.pacientes],
            ["Médicos", k.medicos],
            ["Consultas", k.consultas],
            ["Retornos", k.retornos],
            ["% particulares", k.pct_particulares + "%"],
            ["Medicamentos / receita", k.media_medicamentos_por_receita],
        ].map(([rotulo, valor]) => `<div class="kpi"><span>${rotulo}</span><strong>${valor}</strong></div>`).join("");

        grafico("g-especialidade", "bar", d.consultasPorEspecialidade, { indexAxis: "y" });
        grafico("g-convenio", "doughnut", d.pacientesComSemConvenio);
        grafico("g-medicamentos", "bar", d.topMedicamentos, { indexAxis: "y" });
        grafico("g-exames", "bar", d.topExames, { indexAxis: "y" });
        grafico("g-dist-consultas", "bar", d.distribuicaoConsultasPorPaciente, {}, "Nº de consultas", "Nº de pacientes");
        grafico("g-dist-alergias", "bar", d.distribuicaoAlergias, {}, "Nº de alergias", "Nº de pacientes");
    } catch (e) {
        avisar(e.message, true);
    }
}

function grafico(id, tipo, linhas, extra = {}, tituloX, tituloY) {
    if (graficos[id]) graficos[id].destroy();
    const pizza = tipo === "doughnut";
    const eixos = pizza ? {} : {
        x: { beginAtZero: true, ticks: { precision: 0 }, title: { display: !!tituloX, text: tituloX } },
        y: { beginAtZero: true, ticks: { precision: 0, autoSkip: false }, title: { display: !!tituloY, text: tituloY } },
    };
    graficos[id] = new Chart(document.getElementById(id), {
        type: tipo,
        data: {
            labels: linhas.map(l => l.rotulo),
            datasets: [{
                data: linhas.map(l => Number(l.valor)),
                backgroundColor: pizza ? PALETA : COR,
                borderRadius: pizza ? 0 : 4,
                borderWidth: pizza ? 2 : 0,
            }],
        },
        options: {
            maintainAspectRatio: false,
            plugins: { legend: { display: pizza, position: "bottom" } },
            scales: eixos,
            ...extra,
        },
    });
}

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
            { nome: "codigo_convenio", rotulo: "Convênio", tipo: "convenio" },
            { nome: "telefone", rotulo: "Telefone", dica: "10 ou 11 dígitos com DDD", padrao: "[0-9]{10,11}", soNoCadastro: true },
        ],
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
    convenios: {
        singular: "convênio",
        chave: "codigo",
        colunas: [["codigo", "Código"], ["nome", "Nome"], ["total_pacientes", "Pacientes"]],
        campos: [
            { nome: "codigo", rotulo: "Código", tipo: "number", obrigatorio: true, soNaEdicao: true },
            { nome: "nome", rotulo: "Nome do plano", obrigatorio: true },
        ],
    },
};

const dados = {};

async function carregarEntidade(nome) {
    try {
        dados[nome] = await api.get("/api/" + nome);
        desenharTabela(nome);
    } catch (e) {
        avisar(e.message, true);
    }
}

function desenharTabela(nome) {
    const cfg = ENTIDADES[nome];
    const filtro = document.querySelector(`[data-busca="${nome}"]`).value.toLowerCase();
    const linhas = (dados[nome] || []).filter(l =>
        !filtro || Object.values(l).some(v => v !== null && String(v).toLowerCase().includes(filtro)));

    const cabecalho = cfg.colunas.map(([, titulo]) => `<th>${titulo}</th>`).join("") + "<th></th>";
    const corpo = linhas.map(l => `<tr>${cfg.colunas.map(([c]) => celula(l[c])).join("")}
        <td class="acoes-linha">
            <button class="btn pequeno" data-editar="${escapar(l[cfg.chave])}">Editar</button>
            <button class="btn pequeno perigo" data-excluir="${escapar(l[cfg.chave])}">Excluir</button>
        </td></tr>`).join("");
    const tabela = document.getElementById("tabela-" + nome);
    tabela.innerHTML = `<thead><tr>${cabecalho}</tr></thead><tbody>${corpo}</tbody>`;

    tabela.querySelectorAll("[data-editar]").forEach(b => b.addEventListener("click", () =>
        abrirFormulario(nome, (dados[nome]).find(l => String(l[cfg.chave]) === b.dataset.editar))));
    tabela.querySelectorAll("[data-excluir]").forEach(b => b.addEventListener("click", () => excluir(nome, b.dataset.excluir)));
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

const modal = document.getElementById("modal");
const formulario = document.getElementById("formulario");
let edicao = null;

document.getElementById("modal-cancelar").addEventListener("click", () => modal.close());

async function abrirFormulario(nome, registro) {
    const cfg = ENTIDADES[nome];
    edicao = { nome, chave: registro ? registro[cfg.chave] : null };
    document.getElementById("modal-titulo").textContent = (registro ? "Editar " : "Novo ") + cfg.singular;
    document.getElementById("modal-erro").textContent = "";

    let convenios = [];
    if (cfg.campos.some(c => c.tipo === "convenio")) {
        convenios = await api.get("/api/convenios");
    }

    const campos = cfg.campos.filter(c => registro ? !c.soNoCadastro : !c.soNaEdicao);
    document.getElementById("modal-campos").innerHTML = campos.map(c => {
        const valor = registro && registro[c.nome] !== null && registro[c.nome] !== undefined ? registro[c.nome] : "";
        const atributos = `name="${c.nome}" id="f-${c.nome}" ${c.obrigatorio ? "required" : ""} ${c.padrao ? `pattern="${c.padrao}"` : ""}`;
        let entrada;
        if (c.tipo === "convenio") {
            entrada = `<select ${atributos}><option value="">Particular (sem convênio)</option>` +
                convenios.map(cv => `<option value="${cv.codigo}" ${cv.codigo === valor ? "selected" : ""}>${escapar(cv.nome)}</option>`).join("") +
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
        document.getElementById("modal-erro").textContent = e.message;
    }
});

async function carregarRelatorios() {
    const lista = document.getElementById("lista-relatorios");
    if (lista.children.length) return;
    try {
        const relatorios = await api.get("/api/relatorios");
        lista.innerHTML = relatorios.map(r =>
            `<li><button data-id="${r.id}"><strong>${r.id}. ${escapar(r.titulo)}</strong><small>${escapar(r.tecnica)}</small></button></li>`).join("");
        lista.querySelectorAll("button").forEach(b => b.addEventListener("click", () => executarRelatorio(b)));
    } catch (e) {
        avisar(e.message, true);
    }
}

async function executarRelatorio(botao) {
    document.querySelectorAll("#lista-relatorios button").forEach(b => b.classList.toggle("ativo", b === botao));
    const alvo = document.getElementById("resultado-relatorio");
    try {
        const r = await api.get("/api/relatorios/" + botao.dataset.id);
        alvo.classList.remove("vazio");
        alvo.innerHTML = `<h2>${escapar(r.titulo)}</h2>
            <pre class="sql">${escapar(r.sql)}</pre>
            <p class="contagem">${r.rows.length} linha(s)</p>
            <div class="tabela-wrap"><table>
                <thead><tr>${r.columns.map(c => `<th>${escapar(c)}</th>`).join("")}</tr></thead>
                <tbody>${r.rows.map(l => `<tr>${l.map(celula).join("")}</tr>`).join("")}</tbody>
            </table></div>`;
    } catch (e) {
        avisar(e.message, true);
    }
}

carregarDashboard();

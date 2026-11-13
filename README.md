# Sistema de Prontuário Médico (Clínica VidaPlena) — Projeto de Banco de Dados

**Integrantes:** Arthur Sindeaux, Arthur Oliveira, Lucas Pinto, João Henrique Bastos

**Repositório:** https://github.com/lucasbeno/BD-sistema-Prontuario_medico

Aplicação para gerenciar uma clínica médica: pacientes, médicos, convênios, consultas,
retornos, receitas, medicamentos, exames e alergias, com um dashboard estatístico
calculado direto do banco.

- **Backend:** Java 17+ com JDBC puro — todo comando SQL é explícito, em `PreparedStatement` / `CallableStatement`
- **Banco:** MySQL 8.0.13+
- **Interface:** página web servida pelo próprio Java (HTML/CSS/JS + Chart.js 4.4.1, incluído em `web/lib/`, funciona sem internet)

---

## Como executar

1. **Criar o banco** — rode **um único arquivo**, que apaga e recria tudo na ordem certa:
   ```
   mysql -u root -p < sql/instalar_tudo.sql
   ```
   No MySQL Workbench: *File → Open SQL Script* → `sql/instalar_tudo.sql` → clique no raio (⚡).

   (Ele é a junção de `01_tabelas`, `02_insercao`, `04_indices`, `04_visoes`, `05_funcoes`,
   `05_procedimentos`, `05_triggers` e `06_dashboard`, nessa ordem. Rodar um por um dá o mesmo resultado.)

2. **Configurar a conexão:** copie `db.properties.exemplo` para `db.properties` e coloque o usuário/senha do seu MySQL.

3. **Rodar a aplicação** (JDK 17 ou superior):
   - Windows: dois cliques em `executar.bat`
   - Linux/macOS: `sh executar.sh`
   - IntelliJ/Eclipse: marque `src` como pasta de código, adicione o jar de `lib/` como biblioteca e rode
     `prontuario.App` com a pasta do projeto como diretório de trabalho

4. Abra **http://localhost:8080**.

---

## Requisitos da Etapa 06 → onde estão

| Requisito | Onde está na interface | Código |
|---|---|---|
| **CRUD em ao menos 4 tabelas** | 6 abas de cadastro: **Pacientes**, **Médicos**, **Consultas**, **Convênios**, **Medicamentos**, **Exames** — inserir, listar/buscar, editar e excluir. Em Pacientes → *Alergias*; em Consultas → *Receita e exames* (receita, itens da receita e exames pedidos) | `dao/PacienteDAO`, `MedicoDAO`, `ConsultaDAO`, `ConvenioDAO`, `CatalogoDAO`, `AlergiaDAO` |
| **Integração com funções, procedimentos e triggers (Etapa 05)** | Aba **Funções, procedimentos e triggers**: executa as 2 funções, os 2 procedimentos (um com cursor, com opção de simular com ROLLBACK ou confirmar com COMMIT), testa o trigger de alergia e mostra o log gravado pelo trigger de convênio. Também mostra o código dos objetos lido de `information_schema` | `dao/RegrasDAO` |
| | Os efeitos também aparecem no uso normal: prescrever um medicamento ao qual o paciente é alérgico (aba Consultas) é **bloqueado pelo trigger**; trocar o convênio de um paciente (aba Pacientes) gera linha no **log**; o dashboard usa `fn_classificar_polifarmacia` no gráfico de pizza | |
| **Consultas e views das Etapas 03 e 04 na interface, com filtros** | Aba **Consultas e visões**: 8 consultas da Etapa 03, 4 consultas avançadas e 2 visões da Etapa 04. Cada uma tem filtros (texto, lista, mínimo, datas, Top N), indicadores, gráfico, tabela, o SQL original e o SQL executado | `dao/RelatorioDAO` |
| **Dashboard estatístico com dados do banco** | Aba **Dashboard** | `dao/DashboardDAO` |
| ↳ Indicadores resumidos | 8 indicadores do período (consultas e variação % sobre o período anterior, pacientes atendidos, médicos ativos, consultas/mês, % retornos, % particulares, medicamentos por receita, exames por consulta) + totais do cadastro | |
| ↳ Ao menos 6 gráficos dinâmicos | **8 gráficos**: barras empilhadas + linhas (consultas por mês), barras (especialidade), pizza (situação de medicação), histograma (distribuição de frequência), barras (Top 10), radar (perfil das especialidades), dispersão (correlação) e barras (dia da semana) — além da tabela de estatística descritiva | |
| ↳ Média, mediana, moda, variância, desvio padrão | Calculados **no MySQL** (`AVG`, `ROW_NUMBER()` para a mediana, `GROUP BY` para a moda, `VAR_SAMP`, `STDDEV_SAMP`, coeficiente de variação) para 5 variáveis | |
| ↳ Distribuições / comparativos de frequência | Histograma com seletor de variável; consultas por especialidade e por dia da semana; Top 10 medicamentos/exames | |
| ↳ Correlações ou tendências temporais | Série mensal com média móvel de 3 meses (função de janela) e reta de tendência por mínimos quadrados; dispersão consultas × medicamentos distintos com **correlação de Pearson** calculada em SQL | |
| ↳ Visualizações interativas com filtros | Filtros de **período** (datas + atalhos), **especialidade**, **forma de pagamento** (particular / convênio / convênio específico) e **tipo de consulta**; clicar numa barra de especialidade filtra o dashboard; tooltips em todos os gráficos; “Dados e SQL” em cada cartão mostra a tabela e o comando executado | |

---

## O que mudou no banco na Etapa 06 (`sql/06_dashboard.sql`)

- **`consulta.data_consulta DATE NOT NULL DEFAULT (CURRENT_DATE)`** — sem a data da consulta não
  havia como fazer tendência temporal nem filtro por período, que a Etapa 06 pede. As 64 consultas já
  cadastradas receberam datas entre nov/2025 e out/2026 (dias úteis, retorno sempre depois da consulta de
  origem). O `DEFAULT` mantém o procedimento `sp_agendar_pacientes_sem_consulta` funcionando sem alteração.
- Índice **`idx_consulta_data`** para os filtros por período.
- Visão **`vw_atendimento_completo`** recriada com a coluna `data_consulta` (o resto é idêntico à Etapa 04).
- Correção em `sql/04_indices.sql`: havia um `.` solto na linha 2 que fazia o script dar erro de sintaxe.
- `sql/instalar_tudo.sql` começa com `SET NAMES utf8mb4` para os acentos não quebrarem em clientes configurados em latin1.

---

## Estrutura

```
sql/
  instalar_tudo.sql        TUDO em um arquivo (é o que precisa rodar)
  01_tabelas.sql           criação do banco, tabelas e triggers de integridade (Etapa 03)
  02_insercao.sql          inserção dos dados
  03_consultas.sql         8 consultas (Etapa 03)
  04_indices.sql           índices (Etapa 04)
  04_consultas_avancadas.sql  4 consultas avançadas (Etapa 04)
  04_visoes.sql            2 visões (Etapa 04)
  05_funcoes.sql           2 funções (Etapa 05)
  05_procedimentos.sql     2 procedimentos, um com cursor (Etapa 05)
  05_triggers.sql          tabela log_auditoria + 2 triggers (Etapa 05)
  06_dashboard.sql         data da consulta, índice e visão atualizada (Etapa 06)
  postgresql_entrega2/     scripts originais da Etapa 02 (PostgreSQL)
src/prontuario/
  App.java                 servidor HTTP + rotas da API (/api/...)
  Database.java            conexão JDBC (lê db.properties) e utilitários
  Json.java                conversão para JSON
  dao/PacienteDAO.java     pessoa + paciente + telefone
  dao/MedicoDAO.java       pessoa + medico
  dao/ConsultaDAO.java     consulta + retorno + prescricao + contem + solicita
  dao/ConvenioDAO.java     convenio
  dao/CatalogoDAO.java     medicamento e exame
  dao/AlergiaDAO.java      alergia
  dao/RelatorioDAO.java    consultas das Etapas 03/04 e visões, com filtros
  dao/RegrasDAO.java       funções, procedimentos e triggers da Etapa 05
  dao/DashboardDAO.java    indicadores, gráficos e estatística do dashboard
web/                       interface (index.html, style.css, app.js, lib/chart.umd.min.js)
lib/                       driver JDBC do MySQL (mysql-connector-j 8.4.0)
```

## Restrições do banco que a interface demonstra

- **Triggers:** paciente = médico na consulta é recusado (`trg_consulta_pessoas_*`); retorno igual à origem é
  recusado (`trg_retorno_distinta_*`); prescrição de medicamento com alergia é bloqueada
  (`trg_contem_bloqueia_alergia`); troca de convênio vira log (`trg_paciente_log_convenio`).
- **ON UPDATE CASCADE:** alterar CPF de paciente/médico, código de convênio ou de medicamento propaga para as tabelas filhas.
- **ON DELETE CASCADE:** excluir uma consulta apaga receita, itens, exames pedidos e vínculos de retorno.
- **ON DELETE SET NULL:** excluir um convênio deixa os pacientes dele como particulares.
- **ON DELETE RESTRICT:** paciente/médico com consultas e medicamento/exame já usados não podem ser excluídos (a interface mostra o aviso).
- **CHECK / UNIQUE / DEFAULT / AUTO_INCREMENT:** CPF, CEP, CRM e telefone inválidos ou duplicados são recusados;
  especialidade vazia vira “Clínica Geral”, número vazio vira “S/N”, receita sem nome vira “Receita padrão”;
  prontuário a partir de 1001 e receita a partir de 5001.

## Consultas (`sql/03_consultas.sql` e `sql/04_consultas_avancadas.sql`)

**Etapa 03:** 1. consultas com paciente e médico (JOIN de 5 tabelas) · 2. consultas por especialidade ·
3. Top N medicamentos · 4. pacientes com mais de uma alergia (HAVING) · 5. pacientes por convênio (LEFT JOIN) ·
6. médicos acima da média (HAVING com subconsultas) · 7. pacientes sem consulta (NOT EXISTS) ·
8. retornos com medicamentos e exames (auto-relacionamento)

**Etapa 04:** 1. convênios sem paciente (anti join) · 2. exames na 1ª consulta × retorno (FULL OUTER JOIN emulado) ·
3. alerta de reatividade cruzada a anti-inflamatórios (IN + EXISTS) · 4. pacientes acima da média de medicamentos
(tabela derivada + subconsulta escalar) · visões `vw_prontuario_paciente` e `vw_atendimento_completo`

## Ajustes em relação às etapas anteriores

Os scripts da Etapa 02 foram escritos para PostgreSQL e convertidos para MySQL na Etapa 03 (originais em
`sql/postgresql_entrega2/`): `SEQUENCE` → `AUTO_INCREMENT`; `~` → `REGEXP`; `btrim` → `TRIM`; os `CHECK` que o
MySQL não aceita em colunas `AUTO_INCREMENT` ou em FKs com `CASCADE` viraram triggers com a mesma regra.

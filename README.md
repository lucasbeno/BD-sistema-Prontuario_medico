# Sistema de Prontuário Médico — Projeto de Banco de Dados

**Integrantes:** Arthur Sindeaux, Arthur Oliveira, Lucas Pinto, João Henrique Bastos

Aplicação para gerenciar uma clínica médica: pacientes, médicos, convênios,
consultas, retornos, prescrições, medicamentos e exames.

- **Backend:** Java 17+ com JDBC puro (todos os comandos SQL são explícitos, em `PreparedStatement`)
- **Banco:** MySQL 8+
- **Interface:** página web servida pelo próprio Java (HTML/CSS/JS + Chart.js)

## Estrutura

```
sql/
  01_tabelas.sql           criação do banco e das tabelas (MySQL)
  02_insercao.sql          inserção dos dados (>= 30 tuplas por tabela)
  03_consultas.sql         consultas da Etapa 03
  postgresql_entrega2/     scripts originais da Etapa 02 (PostgreSQL)
src/prontuario/
  App.java                 servidor HTTP + rotas da API
  Database.java            conexão JDBC (lê db.properties)
  Json.java                conversão para JSON
  dao/PacienteDAO.java     INSERT/UPDATE/DELETE/SELECT de pacientes
  dao/MedicoDAO.java       INSERT/UPDATE/DELETE/SELECT de médicos
  dao/ConvenioDAO.java     INSERT/UPDATE/DELETE/SELECT de convênios
  dao/RelatorioDAO.java    as 8 consultas da aba "Consultas SQL"
  dao/DashboardDAO.java    indicadores e dados dos gráficos
web/                       interface (index.html, style.css, app.js)
lib/                       driver JDBC do MySQL (mysql-connector-j)
```

## Como executar

1. **Criar o banco** (no MySQL Workbench, ou pelo terminal):
   ```
   mysql -u root -p < sql/01_tabelas.sql
   mysql -u root -p < sql/02_insercao.sql
   ```
   No Workbench: abra cada arquivo e execute com o raio (⚡), primeiro o `01`, depois o `02`.

2. **Configurar a conexão:** copie `db.properties.exemplo` para `db.properties` e
   coloque o usuário/senha do seu MySQL.

3. **Rodar a aplicação** (precisa do JDK 17 ou superior):
   - Windows: dê dois cliques em `executar.bat`
   - Linux/macOS: `sh executar.sh`
   - IntelliJ/Eclipse: marque `src` como pasta de código, adicione o jar de `lib/`
     como biblioteca e rode `prontuario.App` (com a pasta do projeto como diretório de trabalho)

4. Abra **http://localhost:8080** no navegador.

## O que a interface faz

| Requisito da Etapa 03 | Onde está |
|---|---|
| Inserção / alteração / deleção em ao menos 2 tabelas | Abas **Pacientes**, **Médicos** e **Convênios** |
| Visualização de dados | Tabelas com busca em cada aba |
| Gráficos (disciplina de estatística) | Aba **Dashboard** |
| Resultados das consultas | Aba **Consultas SQL** (mostra o SQL e o resultado) |
| Ao menos 4 consultas, 1 com JOIN | 8 consultas em `sql/03_consultas.sql` (todas usam JOIN) |
| Java + MySQL com SQL explícito | `src/prontuario/dao/*.java` (JDBC) |

Restrições do banco demonstradas pela interface:

- **ON UPDATE CASCADE:** alterar o CPF de um paciente propaga para `paciente`, `telefone`,
  `alergia` e `consulta`; alterar o código de um convênio propaga para `paciente`.
- **ON DELETE SET NULL:** excluir um convênio deixa os pacientes dele como particulares.
- **ON DELETE RESTRICT:** paciente/médico com consultas não pode ser excluído (a interface mostra o aviso).
- **CHECK / UNIQUE / DEFAULT:** CPF, CEP, CRM e telefone inválidos ou duplicados são recusados;
  especialidade vazia vira “Clínica Geral” e número vazio vira “S/N”.
- **AUTO_INCREMENT** (no lugar das sequences do PostgreSQL): código do convênio, nº do prontuário
  (a partir de 1001) e nº da prescrição (a partir de 5001).

## Consultas (`sql/03_consultas.sql`)

1. Consultas com paciente e médico responsável — JOIN de 5 tabelas
2. Total de consultas por especialidade — JOIN + GROUP BY
3. Top 10 medicamentos mais prescritos — JOIN + GROUP BY + LIMIT
4. Pacientes com mais de uma alergia — JOIN + GROUP BY + HAVING
5. Pacientes por convênio (inclui particulares) — LEFT JOIN + COALESCE
6. Médicos com consultas acima da média — HAVING com subconsultas
7. Pacientes que nunca passaram por consulta — NOT EXISTS
8. Retornos com medicamentos e exames — auto-relacionamento + subconsultas correlacionadas

## Ajustes em relação às etapas anteriores

Os scripts da Etapa 02 foram escritos para PostgreSQL. Como a Etapa 03 exige MySQL,
eles foram convertidos (os originais estão em `sql/postgresql_entrega2/`):

- `SEQUENCE`/`nextval` → `AUTO_INCREMENT`; `~` → `REGEXP`; `btrim` → `TRIM`; `setval` removido.
- O MySQL não aceita `CHECK` em coluna `AUTO_INCREMENT`, então `ck_paciente_prontuario` e
  `ck_prescricao_numero` saíram (o AUTO_INCREMENT já garante valor > 0).
- O MySQL não aceita `CHECK` em colunas de FK com ação `CASCADE`, então
  `ck_consulta_pessoas` e `ck_retorno_distinta` viraram **triggers** com a mesma regra.

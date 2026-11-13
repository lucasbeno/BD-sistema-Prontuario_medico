package prontuario.dao;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/**
 * Consultas da Etapa 03, consultas avançadas da Etapa 04 e as duas visões da Etapa 04.
 *
 * Cada item guarda o SQL original da etapa. Para aplicar os filtros escolhidos na tela
 * sem reescrever a consulta, o SQL original vira uma tabela derivada:
 *
 *   SELECT * FROM ( <SQL da etapa> ) AS resultado
 *    WHERE <filtros escolhidos>      -- sempre com parâmetros (?)
 *    ORDER BY <ordem original>
 *    LIMIT ?                         -- só nas consultas de "Top N"
 */
public class RelatorioDAO {

    /** tipo: texto (LIKE), opcao (=), min (>=), max (<=), de/ate (datas), limite (LIMIT). */
    public record Filtro(String nome, String rotulo, String tipo, String coluna,
                         Object padrao, List<String> opcoes, String opcoesSql) {
        static Filtro texto(String coluna, String rotulo) {
            return new Filtro(coluna, rotulo, "texto", coluna, null, null, null);
        }

        static Filtro opcao(String coluna, String rotulo, String opcoesSql) {
            return new Filtro(coluna, rotulo, "opcao", coluna, null, null, opcoesSql);
        }

        static Filtro opcao(String coluna, String rotulo, List<String> opcoes) {
            return new Filtro(coluna, rotulo, "opcao", coluna, null, opcoes, null);
        }

        static Filtro minimo(String coluna, String rotulo) {
            return new Filtro("min_" + coluna, rotulo, "min", coluna, null, null, null);
        }

        static Filtro dataDe(String coluna, String rotulo) {
            return new Filtro("de_" + coluna, rotulo, "de", coluna, null, null, null);
        }

        static Filtro dataAte(String coluna, String rotulo) {
            return new Filtro("ate_" + coluna, rotulo, "ate", coluna, null, null, null);
        }

        static Filtro limite(int padrao) {
            return new Filtro("limite", "Quantidade (Top N)", "limite", null, padrao, null, null);
        }
    }

    /**
     * Como desenhar o resultado. tipo: barra, barra-h, rosca, linha.
     * rotulo = coluna do eixo/categoria; valores = colunas numéricas (uma série cada);
     * agrupar = conta quantas linhas há para cada valor dessa coluna (quando não há coluna numérica).
     */
    public record Grafico(String tipo, String titulo, String rotulo, List<String> valores, String agrupar) {
        static Grafico de(String tipo, String titulo, String rotulo, String... valores) {
            return new Grafico(tipo, titulo, rotulo, List.of(valores), null);
        }

        static Grafico contando(String tipo, String titulo, String agrupar) {
            return new Grafico(tipo, titulo, null, List.of(), agrupar);
        }
    }

    /** Indicador calculado sobre as linhas retornadas. tipo: linhas, soma, media, max, primeiro, distintos. */
    public record Indicador(String rotulo, String tipo, String coluna) {
    }

    public record Relatorio(String id, String etapa, String titulo, String tecnica, String pergunta,
                            String sql, String ordem, List<Filtro> filtros, Grafico grafico,
                            List<Indicador> indicadores) {
    }

    private static final String ESPECIALIDADES = "SELECT DISTINCT especialidade FROM medico ORDER BY 1";
    private static final String CONVENIOS = """
            SELECT nome FROM (SELECT 'Particular' AS nome, 0 AS o
                              UNION ALL SELECT nome, 1 FROM convenio) t ORDER BY o, nome""";

    private static final List<Relatorio> RELATORIOS = List.of(
            // ============================== ETAPA 03 ==============================
            new Relatorio("03-1", "Consultas", "Consultas com paciente e médico responsável",
                    "JOIN de 5 tabelas (pessoa usada 2x)",
                    "Quem atendeu quem, em qual especialidade?",
                    """
                    SELECT
                        c.codigo                AS codigo_consulta,
                        p_pac.nome              AS paciente,
                        pac.numero_prontuario   AS prontuario,
                        p_med.nome              AS medico,
                        m.especialidade         AS especialidade,
                        m.crm                   AS crm
                    FROM consulta c
                    JOIN paciente pac   ON pac.cpf  = c.cpf_paciente
                    JOIN pessoa   p_pac ON p_pac.cpf = pac.cpf
                    JOIN medico   m     ON m.cpf    = c.cpf_medico
                    JOIN pessoa   p_med ON p_med.cpf = m.cpf
                    ORDER BY c.codigo""",
                    "codigo_consulta",
                    List.of(Filtro.opcao("especialidade", "Especialidade", ESPECIALIDADES),
                            Filtro.texto("paciente", "Paciente contém"),
                            Filtro.texto("medico", "Médico contém")),
                    Grafico.contando("barra-h", "Consultas por especialidade (linhas do resultado)", "especialidade"),
                    List.of(new Indicador("Consultas", "linhas", null),
                            new Indicador("Pacientes distintos", "distintos", "prontuario"),
                            new Indicador("Médicos distintos", "distintos", "crm"))),

            new Relatorio("03-2", "Consultas", "Total de consultas por especialidade",
                    "JOIN + GROUP BY + COUNT",
                    "Quais especialidades concentram mais atendimentos?",
                    """
                    SELECT
                        m.especialidade      AS especialidade,
                        COUNT(*)             AS total_consultas
                    FROM consulta c
                    JOIN medico m ON m.cpf = c.cpf_medico
                    GROUP BY m.especialidade
                    ORDER BY total_consultas DESC""",
                    "total_consultas DESC, especialidade",
                    List.of(Filtro.minimo("total_consultas", "Mínimo de consultas")),
                    Grafico.de("barra-h", "Consultas por especialidade", "especialidade", "total_consultas"),
                    List.of(new Indicador("Especialidades", "linhas", null),
                            new Indicador("Total de consultas", "soma", "total_consultas"),
                            new Indicador("Média por especialidade", "media", "total_consultas"))),

            new Relatorio("03-3", "Consultas", "Top N medicamentos mais prescritos",
                    "JOIN + GROUP BY + ORDER BY + LIMIT",
                    "Quais medicamentos a clínica mais receita?",
                    """
                    SELECT
                        med.nome              AS medicamento,
                        COUNT(*)              AS vezes_prescrito
                    FROM contem ct
                    JOIN medicamento med ON med.codigo = ct.codigo_medicamento
                    GROUP BY med.nome
                    ORDER BY vezes_prescrito DESC, medicamento ASC""",
                    "vezes_prescrito DESC, medicamento ASC",
                    List.of(Filtro.limite(10)),
                    Grafico.de("barra-h", "Vezes prescrito", "medicamento", "vezes_prescrito"),
                    List.of(new Indicador("Medicamentos listados", "linhas", null),
                            new Indicador("Prescrições somadas", "soma", "vezes_prescrito"),
                            new Indicador("Mais prescrito (vezes)", "max", "vezes_prescrito"))),

            new Relatorio("03-4", "Consultas", "Pacientes com mais de uma alergia",
                    "JOIN + GROUP BY + HAVING",
                    "Quem exige mais cuidado na hora de prescrever?",
                    """
                    SELECT
                        p.nome                  AS paciente,
                        pac.numero_prontuario   AS prontuario,
                        COUNT(*)                AS quantidade_alergias
                    FROM alergia a
                    JOIN paciente pac ON pac.cpf = a.cpf
                    JOIN pessoa   p   ON p.cpf   = pac.cpf
                    GROUP BY p.nome, pac.numero_prontuario
                    HAVING COUNT(*) > 1
                    ORDER BY quantidade_alergias DESC, paciente""",
                    "quantidade_alergias DESC, paciente",
                    List.of(Filtro.texto("paciente", "Paciente contém"),
                            Filtro.minimo("quantidade_alergias", "Mínimo de alergias")),
                    Grafico.de("barra-h", "Alergias por paciente", "paciente", "quantidade_alergias"),
                    List.of(new Indicador("Pacientes", "linhas", null),
                            new Indicador("Máximo de alergias", "max", "quantidade_alergias"))),

            new Relatorio("03-5", "Consultas", "Pacientes por convênio (inclui particulares)",
                    "LEFT JOIN + COALESCE + GROUP BY",
                    "Como os pacientes se distribuem entre convênios e particular?",
                    """
                    SELECT
                        COALESCE(cv.nome, 'Particular (sem convênio)') AS convenio,
                        COUNT(*)                                        AS total_pacientes
                    FROM paciente pac
                    LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
                    GROUP BY COALESCE(cv.nome, 'Particular (sem convênio)')
                    ORDER BY total_pacientes DESC""",
                    "total_pacientes DESC, convenio",
                    List.of(Filtro.texto("convenio", "Convênio contém"),
                            Filtro.minimo("total_pacientes", "Mínimo de pacientes")),
                    Grafico.de("barra-h", "Pacientes por convênio", "convenio", "total_pacientes"),
                    List.of(new Indicador("Convênios no resultado", "linhas", null),
                            new Indicador("Pacientes", "soma", "total_pacientes"),
                            new Indicador("Média por convênio", "media", "total_pacientes"))),

            new Relatorio("03-6", "Consultas", "Médicos com consultas acima da média da clínica",
                    "JOIN + GROUP BY + HAVING com subconsultas",
                    "Quais médicos estão mais carregados que a média?",
                    """
                    SELECT
                        p.nome                   AS medico,
                        m.especialidade          AS especialidade,
                        COUNT(c.codigo)          AS total_consultas,
                        ROUND((SELECT COUNT(*) FROM consulta) / (SELECT COUNT(*) FROM medico), 2) AS media_por_medico
                    FROM medico m
                    JOIN pessoa   p ON p.cpf        = m.cpf
                    JOIN consulta c ON c.cpf_medico = m.cpf
                    GROUP BY m.cpf, p.nome, m.especialidade
                    HAVING COUNT(c.codigo) > (SELECT COUNT(*) FROM consulta) / (SELECT COUNT(*) FROM medico)
                    ORDER BY total_consultas DESC, medico""",
                    "total_consultas DESC, medico",
                    List.of(Filtro.opcao("especialidade", "Especialidade", ESPECIALIDADES)),
                    Grafico.de("barra-h", "Consultas do médico x média da clínica", "medico",
                            "total_consultas", "media_por_medico"),
                    List.of(new Indicador("Médicos acima da média", "linhas", null),
                            new Indicador("Média da clínica", "primeiro", "media_por_medico"))),

            new Relatorio("03-7", "Consultas", "Pacientes que nunca passaram por consulta",
                    "NOT EXISTS (subconsulta correlacionada) + LEFT JOIN",
                    "Quem está cadastrado mas ainda não foi atendido?",
                    """
                    SELECT
                        p.nome                           AS paciente,
                        pac.numero_prontuario            AS prontuario,
                        COALESCE(cv.nome, 'Particular')  AS convenio
                    FROM paciente pac
                    JOIN pessoa p         ON p.cpf     = pac.cpf
                    LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM consulta c
                        WHERE c.cpf_paciente = pac.cpf
                    )
                    ORDER BY p.nome""",
                    "paciente",
                    List.of(Filtro.texto("convenio", "Convênio contém")),
                    Grafico.contando("rosca", "Pacientes sem consulta por convênio", "convenio"),
                    List.of(new Indicador("Pacientes sem consulta", "linhas", null))),

            new Relatorio("03-8", "Consultas", "Retornos: o que foi prescrito e solicitado",
                    "Auto-relacionamento + subconsultas correlacionadas + GROUP_CONCAT",
                    "O que acontece nas consultas de retorno?",
                    """
                    SELECT
                        r.codigo_consulta_origem    AS consulta_origem,
                        r.codigo_consulta_retorno   AS consulta_retorno,
                        pp.nome                     AS paciente,
                        pm.nome                     AS medico_retorno,
                        (SELECT COUNT(*)
                           FROM contem ct
                          WHERE ct.codigo_consulta = r.codigo_consulta_retorno) AS qtd_medicamentos,
                        (SELECT GROUP_CONCAT(e.nome ORDER BY e.nome SEPARATOR ', ')
                           FROM solicita s
                           JOIN exame e ON e.codigo = s.codigo_exame
                          WHERE s.codigo_consulta = r.codigo_consulta_retorno)  AS exames_retorno
                    FROM retorno r
                    JOIN consulta co ON co.codigo = r.codigo_consulta_origem
                    JOIN consulta cr ON cr.codigo = r.codigo_consulta_retorno
                    JOIN pessoa   pp ON pp.cpf    = co.cpf_paciente
                    JOIN pessoa   pm ON pm.cpf    = cr.cpf_medico
                    ORDER BY r.codigo_consulta_origem""",
                    "consulta_origem, consulta_retorno",
                    List.of(Filtro.texto("paciente", "Paciente contém"),
                            Filtro.texto("exames_retorno", "Exame contém"),
                            Filtro.minimo("qtd_medicamentos", "Mínimo de medicamentos")),
                    Grafico.contando("barra", "Retornos por quantidade de medicamentos prescritos", "qtd_medicamentos"),
                    List.of(new Indicador("Retornos", "linhas", null),
                            new Indicador("Medicamentos por retorno (média)", "media", "qtd_medicamentos"))),

            // ============================== ETAPA 04 ==============================
            new Relatorio("04-1", "Consultas avançadas", "Convênios credenciados sem nenhum paciente",
                    "ANTI JOIN (LEFT JOIN ... WHERE ... IS NULL)",
                    "Há contratos com convênios que não trazem paciente nenhum?",
                    """
                    SELECT
                        cv.codigo  AS codigo_convenio,
                        cv.nome    AS convenio_sem_pacientes
                    FROM convenio cv
                    LEFT JOIN paciente pac
                           ON pac.codigo_convenio = cv.codigo
                    WHERE pac.cpf IS NULL
                    ORDER BY cv.nome""",
                    "convenio_sem_pacientes",
                    List.of(Filtro.texto("convenio_sem_pacientes", "Nome contém")),
                    null,
                    List.of(new Indicador("Convênios sem paciente", "linhas", null))),

            new Relatorio("04-2", "Consultas avançadas", "Exames pedidos na primeira consulta x no retorno",
                    "FULL OUTER JOIN (LEFT JOIN + UNION ALL + RIGHT JOIN) com CTE",
                    "Quais exames servem para investigar e quais para acompanhar o tratamento?",
                    """
                    WITH exames_primeira_consulta AS (
                        SELECT s.codigo_exame,
                               COUNT(*) AS qtd_pedidos
                        FROM solicita s
                        WHERE NOT EXISTS (SELECT 1
                                            FROM retorno r
                                           WHERE r.codigo_consulta_retorno = s.codigo_consulta)
                        GROUP BY s.codigo_exame
                    ),
                    exames_retorno AS (
                        SELECT s.codigo_exame,
                               COUNT(*) AS qtd_pedidos
                        FROM solicita s
                        WHERE EXISTS (SELECT 1
                                        FROM retorno r
                                       WHERE r.codigo_consulta_retorno = s.codigo_consulta)
                        GROUP BY s.codigo_exame
                    )
                    SELECT
                        e.nome                                    AS exame,
                        resultado.pedidos_primeira_consulta,
                        resultado.pedidos_retorno,
                        CASE
                            WHEN resultado.pedidos_retorno = 0           THEN 'Só investigação (1ª consulta)'
                            WHEN resultado.pedidos_primeira_consulta = 0 THEN 'Só acompanhamento (retorno)'
                            ELSE 'Investigação e acompanhamento'
                        END                                       AS uso_clinico
                    FROM (
                            SELECT COALESCE(pc.codigo_exame, rt.codigo_exame) AS codigo_exame,
                                   COALESCE(pc.qtd_pedidos, 0)                AS pedidos_primeira_consulta,
                                   COALESCE(rt.qtd_pedidos, 0)                AS pedidos_retorno
                            FROM exames_primeira_consulta pc
                            LEFT JOIN exames_retorno rt
                                   ON rt.codigo_exame = pc.codigo_exame

                            UNION ALL

                            SELECT rt.codigo_exame,
                                   0,
                                   rt.qtd_pedidos
                            FROM exames_primeira_consulta pc
                            RIGHT JOIN exames_retorno rt
                                    ON rt.codigo_exame = pc.codigo_exame
                            WHERE pc.codigo_exame IS NULL
                         ) AS resultado
                    JOIN exame e
                      ON e.codigo = resultado.codigo_exame
                    ORDER BY uso_clinico, e.nome""",
                    "uso_clinico, exame",
                    List.of(Filtro.opcao("uso_clinico", "Uso clínico", List.of(
                                    "Só investigação (1ª consulta)", "Só acompanhamento (retorno)",
                                    "Investigação e acompanhamento")),
                            Filtro.texto("exame", "Exame contém")),
                    Grafico.de("barra-h", "Pedidos por exame: 1ª consulta x retorno", "exame",
                            "pedidos_primeira_consulta", "pedidos_retorno"),
                    List.of(new Indicador("Exames", "linhas", null),
                            new Indicador("Pedidos em 1ª consulta", "soma", "pedidos_primeira_consulta"),
                            new Indicador("Pedidos em retorno", "soma", "pedidos_retorno"))),

            new Relatorio("04-3", "Consultas avançadas", "Alerta de reatividade cruzada a anti-inflamatórios",
                    "Subconsultas: IN + EXISTS correlacionada + escalares no SELECT",
                    "Algum paciente alérgico a dipirona/AINEs recebeu outro medicamento do grupo?",
                    """
                    SELECT
                        p.nome                   AS paciente,
                        pac.numero_prontuario    AS prontuario,
                        (SELECT GROUP_CONCAT(a.alergia ORDER BY a.alergia SEPARATOR ', ')
                           FROM alergia a
                          WHERE a.cpf = pac.cpf
                            AND a.alergia IN ('Dipirona', 'Ibuprofeno', 'Anti-inflamatórios')
                        )                        AS alergias_de_risco,
                        (SELECT GROUP_CONCAT(DISTINCT CONCAT(med.nome, ' — consulta ', c.codigo,
                                                             ', Dr(a). ', pm.nome)
                                             ORDER BY c.codigo SEPARATOR ' | ')
                           FROM consulta c
                           JOIN contem      ct  ON ct.codigo_consulta = c.codigo
                           JOIN medicamento med ON med.codigo         = ct.codigo_medicamento
                           JOIN pessoa      pm  ON pm.cpf             = c.cpf_medico
                          WHERE c.cpf_paciente = pac.cpf
                            AND med.nome REGEXP '^(Dipirona|Ibuprofeno|Diclofenaco|Nimesulida)'
                        )                        AS prescricoes_para_revisar
                    FROM paciente pac
                    JOIN pessoa p
                      ON p.cpf = pac.cpf
                    WHERE pac.cpf IN (SELECT a.cpf
                                        FROM alergia a
                                       WHERE a.alergia IN ('Dipirona', 'Ibuprofeno', 'Anti-inflamatórios'))
                      AND EXISTS (SELECT 1
                                    FROM consulta c
                                    JOIN contem      ct  ON ct.codigo_consulta = c.codigo
                                    JOIN medicamento med ON med.codigo         = ct.codigo_medicamento
                                   WHERE c.cpf_paciente = pac.cpf
                                     AND med.nome REGEXP '^(Dipirona|Ibuprofeno|Diclofenaco|Nimesulida)')
                    ORDER BY p.nome""",
                    "paciente",
                    List.of(Filtro.texto("paciente", "Paciente contém"),
                            Filtro.texto("alergias_de_risco", "Alergia contém")),
                    Grafico.contando("rosca", "Pacientes em alerta por alergia de risco", "alergias_de_risco"),
                    List.of(new Indicador("Pacientes em alerta", "linhas", null))),

            new Relatorio("04-4", "Consultas avançadas", "Pacientes com mais medicamentos que a média da clínica",
                    "Subconsultas: tabela derivada no FROM + escalar no WHERE e no SELECT",
                    "Quem usa mais medicamentos diferentes do que o paciente médio?",
                    """
                    SELECT
                        p.nome                                   AS paciente,
                        pac.numero_prontuario                    AS prontuario,
                        por_paciente.qtd_medicamentos            AS medicamentos_distintos,
                        (SELECT ROUND(AVG(t.qtd), 2)
                           FROM (SELECT COUNT(DISTINCT ct2.codigo_medicamento) AS qtd
                                   FROM consulta c2
                                   JOIN contem ct2 ON ct2.codigo_consulta = c2.codigo
                                  GROUP BY c2.cpf_paciente) AS t
                        )                                        AS media_da_clinica,
                        CASE
                            WHEN por_paciente.qtd_medicamentos >= 5 THEN 'Polifarmácia — revisar medicação'
                            ELSE 'Acima da média'
                        END                                      AS situacao
                    FROM (
                            SELECT c.cpf_paciente,
                                   COUNT(DISTINCT ct.codigo_medicamento) AS qtd_medicamentos
                            FROM consulta c
                            JOIN contem ct ON ct.codigo_consulta = c.codigo
                            GROUP BY c.cpf_paciente
                         ) AS por_paciente
                    JOIN paciente pac ON pac.cpf = por_paciente.cpf_paciente
                    JOIN pessoa   p   ON p.cpf   = pac.cpf
                    WHERE por_paciente.qtd_medicamentos >
                          (SELECT AVG(t.qtd)
                             FROM (SELECT COUNT(DISTINCT ct2.codigo_medicamento) AS qtd
                                     FROM consulta c2
                                     JOIN contem ct2 ON ct2.codigo_consulta = c2.codigo
                                    GROUP BY c2.cpf_paciente) AS t)
                    ORDER BY por_paciente.qtd_medicamentos DESC, p.nome""",
                    "medicamentos_distintos DESC, paciente",
                    List.of(Filtro.opcao("situacao", "Situação",
                                    List.of("Polifarmácia — revisar medicação", "Acima da média")),
                            Filtro.minimo("medicamentos_distintos", "Mínimo de medicamentos")),
                    Grafico.de("barra-h", "Medicamentos distintos x média da clínica", "paciente",
                            "medicamentos_distintos", "media_da_clinica"),
                    List.of(new Indicador("Pacientes acima da média", "linhas", null),
                            new Indicador("Média da clínica", "primeiro", "media_da_clinica"),
                            new Indicador("Máximo", "max", "medicamentos_distintos"))),

            // =============================== VISÕES ===============================
            new Relatorio("V-1", "Visões", "vw_prontuario_paciente — folha de rosto do prontuário",
                    "VIEW com 8 tabelas, LEFT JOINs e GROUP_CONCAT(DISTINCT)",
                    "Tudo o que a recepção precisa ver ao abrir o prontuário, em uma linha por paciente.",
                    "SELECT * FROM vw_prontuario_paciente",
                    "prontuario",
                    List.of(Filtro.texto("paciente", "Paciente contém"),
                            Filtro.opcao("convenio", "Convênio", CONVENIOS),
                            Filtro.texto("alergias", "Alergia contém"),
                            Filtro.minimo("total_consultas", "Mínimo de consultas")),
                    Grafico.contando("barra", "Distribuição: nº de consultas por paciente", "total_consultas"),
                    List.of(new Indicador("Pacientes", "linhas", null),
                            new Indicador("Consultas (soma)", "soma", "total_consultas"),
                            new Indicador("Consultas por paciente", "media", "total_consultas"))),

            new Relatorio("V-2", "Visões", "vw_atendimento_completo — registro completo de cada consulta",
                    "VIEW com 7 tabelas + 4 subconsultas",
                    "Cada consulta com paciente, médico, tipo, receita, medicamentos e exames.",
                    "SELECT * FROM vw_atendimento_completo",
                    "data_consulta, codigo_consulta",
                    List.of(Filtro.dataDe("data_consulta", "Data de"),
                            Filtro.dataAte("data_consulta", "Data até"),
                            Filtro.opcao("especialidade", "Especialidade", ESPECIALIDADES),
                            Filtro.opcao("tipo_consulta", "Tipo", List.of("Primeira consulta", "Retorno")),
                            Filtro.texto("paciente", "Paciente contém"),
                            Filtro.texto("medicamentos_prescritos", "Medicamento contém")),
                    Grafico.contando("barra-h", "Atendimentos por especialidade", "especialidade"),
                    List.of(new Indicador("Atendimentos", "linhas", null),
                            new Indicador("Pacientes distintos", "distintos", "prontuario"),
                            new Indicador("Médicos distintos", "distintos", "crm")))
    );

    public List<Map<String, Object>> listar() throws SQLException {
        List<Map<String, Object>> lista = new ArrayList<>();
        try (Connection con = Database.getConnection()) {
            for (Relatorio r : RELATORIOS) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("id", r.id());
                item.put("etapa", r.etapa());
                item.put("titulo", r.titulo());
                item.put("tecnica", r.tecnica());
                item.put("pergunta", r.pergunta());
                item.put("sql", r.sql());
                List<Map<String, Object>> filtros = new ArrayList<>();
                for (Filtro f : r.filtros()) {
                    Map<String, Object> fm = new LinkedHashMap<>();
                    fm.put("nome", f.nome());
                    fm.put("rotulo", f.rotulo());
                    fm.put("tipo", f.tipo());
                    fm.put("padrao", f.padrao());
                    List<String> opcoes = f.opcoes();
                    if (f.opcoesSql() != null) {
                        opcoes = new ArrayList<>();
                        for (Map<String, Object> l : Database.lista(con, f.opcoesSql(), List.of())) {
                            opcoes.add(String.valueOf(l.values().iterator().next()));
                        }
                    }
                    fm.put("opcoes", opcoes);
                    filtros.add(fm);
                }
                item.put("filtros", filtros);
                if (r.grafico() != null) {
                    Map<String, Object> g = new LinkedHashMap<>();
                    g.put("tipo", r.grafico().tipo());
                    g.put("titulo", r.grafico().titulo());
                    g.put("rotulo", r.grafico().rotulo());
                    g.put("valores", r.grafico().valores());
                    g.put("agrupar", r.grafico().agrupar());
                    item.put("grafico", g);
                }
                List<Map<String, Object>> indicadores = new ArrayList<>();
                for (Indicador ind : r.indicadores()) {
                    Map<String, Object> im = new LinkedHashMap<>();
                    im.put("rotulo", ind.rotulo());
                    im.put("tipo", ind.tipo());
                    im.put("coluna", ind.coluna());
                    indicadores.add(im);
                }
                item.put("indicadores", indicadores);
                lista.add(item);
            }
        }
        return lista;
    }

    public Map<String, Object> executar(String id, Map<String, String> valores) throws SQLException {
        Relatorio r = RELATORIOS.stream()
                .filter(x -> x.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Consulta " + id + " não existe"));

        List<String> condicoes = new ArrayList<>();
        List<Object> parametros = new ArrayList<>();
        Integer limite = null;
        for (Filtro f : r.filtros()) {
            String v = valores.get(f.nome());
            if (v == null || v.isBlank()) {
                if (f.padrao() == null) {
                    continue;
                }
                v = String.valueOf(f.padrao());
            }
            v = v.trim();
            String col = "resultado.`" + f.coluna() + "`";
            switch (f.tipo()) {
                case "texto" -> {
                    condicoes.add(col + " LIKE ?");
                    parametros.add("%" + v + "%");
                }
                case "opcao" -> {
                    condicoes.add(col + " = ?");
                    parametros.add(v);
                }
                case "min" -> {
                    condicoes.add(col + " >= ?");
                    parametros.add(Double.valueOf(v));
                }
                case "de" -> {
                    condicoes.add(col + " >= ?");
                    parametros.add(v);
                }
                case "ate" -> {
                    condicoes.add(col + " <= ?");
                    parametros.add(v);
                }
                case "limite" -> limite = Math.max(1, Math.min(100, Integer.parseInt(v)));
                default -> throw new IllegalStateException("Filtro desconhecido: " + f.tipo());
            }
        }

        StringBuilder sql = new StringBuilder("SELECT *\n  FROM (\n");
        for (String linha : r.sql().split("\n")) {
            sql.append("      ").append(linha).append('\n');
        }
        sql.append("       ) AS resultado");
        if (!condicoes.isEmpty()) {
            sql.append("\n WHERE ").append(String.join("\n   AND ", condicoes));
        }
        sql.append("\n ORDER BY ").append(r.ordem());
        if (limite != null) {
            sql.append("\n LIMIT ?");
            parametros.add(limite);
        }

        try (Connection con = Database.getConnection()) {
            Map<String, Object> resultado = Database.tabela(con, sql.toString(), parametros);
            resultado.put("id", r.id());
            resultado.put("titulo", r.titulo());
            resultado.put("sql", r.sql());
            resultado.put("sqlExecutado", comValores(sql.toString(), parametros));
            return resultado;
        }
    }

    /** Só para EXIBIR o SQL executado com os valores no lugar dos "?" (a execução usa PreparedStatement). */
    private static String comValores(String sql, List<Object> parametros) {
        StringBuilder sb = new StringBuilder();
        int p = 0;
        for (char c : sql.toCharArray()) {
            if (c == '?' && p < parametros.size()) {
                Object v = parametros.get(p++);
                sb.append(v instanceof Number ? v.toString() : "'" + String.valueOf(v).replace("'", "''") + "'");
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }
}

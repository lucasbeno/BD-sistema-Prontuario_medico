package prontuario.dao;

import java.sql.Connection;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/**
 * Dashboard estatístico. TODOS os números saem de SELECTs no banco: contagens, médias,
 * mediana e moda (funções de janela), variância e desvio padrão (VAR_SAMP / STDDEV_SAMP),
 * correlação de Pearson e reta de mínimos quadrados (somatórios em SQL).
 *
 * Os filtros da tela (período, especialidade, forma de pagamento e tipo de consulta)
 * viram uma CTE "cf" (consultas filtradas) que é o ponto de partida de todos os gráficos.
 */
public class DashboardDAO {

    /** Filtros escolhidos na tela. */
    public static final class Filtro {
        String inicio;
        String fim;
        String especialidade;
        String pagamento;   // '' todos | 'P' particular | 'C' qualquer convênio | código de um convênio
        String tipo;        // '' todos | 'P' primeira consulta | 'R' retorno

        public Filtro(Map<String, String> q) {
            inicio = vazioNulo(q.get("inicio"));
            fim = vazioNulo(q.get("fim"));
            especialidade = vazioNulo(q.get("especialidade"));
            pagamento = vazioNulo(q.get("pagamento"));
            tipo = vazioNulo(q.get("tipo"));
        }

        private Filtro copiaComPeriodo(String novoInicio, String novoFim) {
            Filtro f = new Filtro(Map.of());
            f.inicio = novoInicio;
            f.fim = novoFim;
            f.especialidade = especialidade;
            f.pagamento = pagamento;
            f.tipo = tipo;
            return f;
        }

        /** CTE "cf" (consultas filtradas) + os parâmetros na ordem dos "?". */
        String cte(List<Object> params) {
            StringBuilder sb = new StringBuilder("""
                    cf AS (
                        SELECT c.codigo, c.cpf_paciente, c.cpf_medico, c.data_consulta,
                               m.especialidade, pac.codigo_convenio,
                               EXISTS (SELECT 1 FROM retorno r
                                        WHERE r.codigo_consulta_retorno = c.codigo) AS eh_retorno
                          FROM consulta c
                          JOIN medico   m   ON m.cpf   = c.cpf_medico
                          JOIN paciente pac ON pac.cpf = c.cpf_paciente
                         WHERE c.data_consulta BETWEEN ? AND ?""");
            params.add(inicio);
            params.add(fim);
            if (especialidade != null) {
                sb.append("\n           AND m.especialidade = ?");
                params.add(especialidade);
            }
            if ("P".equals(pagamento)) {
                sb.append("\n           AND pac.codigo_convenio IS NULL");
            } else if ("C".equals(pagamento)) {
                sb.append("\n           AND pac.codigo_convenio IS NOT NULL");
            } else if (pagamento != null) {
                sb.append("\n           AND pac.codigo_convenio = ?");
                params.add(Integer.valueOf(pagamento));
            }
            if ("P".equals(tipo)) {
                sb.append("\n           AND NOT EXISTS (SELECT 1 FROM retorno r WHERE r.codigo_consulta_retorno = c.codigo)");
            } else if ("R".equals(tipo)) {
                sb.append("\n           AND EXISTS (SELECT 1 FROM retorno r WHERE r.codigo_consulta_retorno = c.codigo)");
            }
            sb.append("\n    )");
            return sb.toString();
        }

        Map<String, Object> comoMapa() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("inicio", inicio);
            m.put("fim", fim);
            m.put("especialidade", especialidade);
            m.put("pagamento", pagamento);
            m.put("tipo", tipo);
            return m;
        }
    }

    /** Variáveis numéricas analisadas na estatística descritiva (uma linha de "v" = uma observação). */
    private record Variavel(String id, String rotulo, String unidade, String sql, int largura) {
    }

    private static final List<Variavel> VARIAVEIS = List.of(
            new Variavel("consultas_paciente", "Consultas por paciente atendido", "consultas",
                    "SELECT COUNT(*) AS x FROM cf GROUP BY cf.cpf_paciente", 1),
            new Variavel("consultas_medico", "Consultas por médico ativo", "consultas",
                    "SELECT COUNT(*) AS x FROM cf GROUP BY cf.cpf_medico", 1),
            new Variavel("medicamentos_receita", "Medicamentos por receita", "medicamentos",
                    """
                    SELECT COUNT(ct.codigo_medicamento) AS x
                      FROM cf
                      JOIN prescricao pr  ON pr.codigo_consulta = cf.codigo
                      LEFT JOIN contem ct ON ct.codigo_consulta = pr.codigo_consulta
                     GROUP BY cf.codigo""", 1),
            new Variavel("exames_consulta", "Exames solicitados por consulta", "exames",
                    """
                    SELECT COUNT(s.codigo_exame) AS x
                      FROM cf
                      LEFT JOIN solicita s ON s.codigo_consulta = cf.codigo
                     GROUP BY cf.codigo""", 1),
            new Variavel("dias_retorno", "Dias entre a consulta e o retorno", "dias",
                    """
                    SELECT DATEDIFF(cf.data_consulta, co.data_consulta) AS x
                      FROM cf
                      JOIN retorno  r  ON r.codigo_consulta_retorno = cf.codigo
                      JOIN consulta co ON co.codigo = r.codigo_consulta_origem""", 7)
    );

    private static final String ESTATISTICAS = """
            SELECT COUNT(*)                                   AS n,
                   ROUND(AVG(x), 2)                           AS media,
                   (SELECT ROUND(AVG(o.x), 2)
                      FROM (SELECT x,
                                   ROW_NUMBER() OVER (ORDER BY x) AS pos,
                                   COUNT(*)     OVER ()           AS total
                              FROM v) AS o
                     WHERE o.pos IN (FLOOR((o.total + 1) / 2), CEIL((o.total + 1) / 2))) AS mediana,
                   (SELECT GROUP_CONCAT(f.x ORDER BY f.x SEPARATOR ', ')
                      FROM (SELECT x, COUNT(*) AS freq FROM v GROUP BY x) AS f
                     WHERE f.freq = (SELECT MAX(f2.freq)
                                       FROM (SELECT COUNT(*) AS freq FROM v GROUP BY x) AS f2)) AS moda,
                   ROUND(VAR_SAMP(x), 3)                      AS variancia,
                   ROUND(STDDEV_SAMP(x), 3)                   AS desvio_padrao,
                   MIN(x)                                     AS minimo,
                   MAX(x)                                     AS maximo,
                   ROUND(100 * STDDEV_SAMP(x) / NULLIF(AVG(x), 0), 1) AS coef_variacao
              FROM v""";

    private static final String FREQUENCIAS = """
            SELECT FLOOR(x / ?) * ? AS faixa,
                   COUNT(*)         AS valor
              FROM v
             GROUP BY faixa
             ORDER BY faixa""";

    /** Correlação de Pearson (r) e reta y = a + b·x por mínimos quadrados, sobre a CTE "pares" (x, y). */
    private static final String REGRESSAO = """
            SELECT n, r, inclinacao, ROUND(media_y - inclinacao * media_x, 4) AS intercepto
              FROM (SELECT COUNT(*) AS n,
                           AVG(x)   AS media_x,
                           AVG(y)   AS media_y,
                           ROUND((COUNT(*) * SUM(x * y) - SUM(x) * SUM(y))
                                 / NULLIF(SQRT((COUNT(*) * SUM(x * x) - SUM(x) * SUM(x))
                                             * (COUNT(*) * SUM(y * y) - SUM(y) * SUM(y))), 0), 4) AS r,
                           ROUND((COUNT(*) * SUM(x * y) - SUM(x) * SUM(y))
                                 / NULLIF(COUNT(*) * SUM(x * x) - SUM(x) * SUM(x), 0), 4) AS inclinacao
                      FROM pares) AS somas""";

    public Map<String, Object> opcoes() throws SQLException {
        Map<String, Object> o = new LinkedHashMap<>();
        try (Connection con = Database.getConnection()) {
            List<String> esp = new ArrayList<>();
            for (Map<String, Object> l : Database.lista(con,
                    "SELECT DISTINCT especialidade FROM medico ORDER BY especialidade", List.of())) {
                esp.add((String) l.get("especialidade"));
            }
            o.put("especialidades", esp);
            o.put("convenios", Database.lista(con, "SELECT codigo, nome FROM convenio ORDER BY nome", List.of()));
            o.putAll(Database.lista(con,
                    "SELECT MIN(data_consulta) AS dataMin, MAX(data_consulta) AS dataMax FROM consulta",
                    List.of()).get(0));
        }
        return o;
    }

    public Map<String, Object> carregar(Map<String, String> query) throws SQLException {
        Filtro f = new Filtro(query);
        Map<String, Object> d = new LinkedHashMap<>();
        Map<String, String> sqls = new LinkedHashMap<>();

        try (Connection con = Database.getConnection()) {
            if (f.inicio == null || f.fim == null) {
                Map<String, Object> lim = Database.lista(con,
                        "SELECT MIN(data_consulta) AS a, MAX(data_consulta) AS b FROM consulta", List.of()).get(0);
                if (f.inicio == null) {
                    f.inicio = lim.get("a") == null ? LocalDate.now().toString() : lim.get("a").toString();
                }
                if (f.fim == null) {
                    f.fim = lim.get("b") == null ? LocalDate.now().toString() : lim.get("b").toString();
                }
            }
            d.put("filtro", f.comoMapa());

            // ---------------------------------------------------- cadastro (sem filtro)
            d.put("cadastro", Database.lista(con, """
                    SELECT (SELECT COUNT(*) FROM paciente)      AS pacientes,
                           (SELECT COUNT(*) FROM medico)        AS medicos,
                           (SELECT COUNT(*) FROM convenio)      AS convenios,
                           (SELECT COUNT(*) FROM medicamento)   AS medicamentos,
                           (SELECT COUNT(*) FROM exame)         AS exames,
                           (SELECT COUNT(*) FROM log_auditoria) AS registros_log""", List.of()).get(0));

            // ------------------------------------------------------------ indicadores
            String kpi = """
                    SELECT COUNT(*)                                  AS consultas,
                           COUNT(DISTINCT cf.cpf_paciente)           AS pacientes_atendidos,
                           COUNT(DISTINCT cf.cpf_medico)             AS medicos_ativos,
                           ROUND(100 * AVG(cf.eh_retorno), 1)        AS pct_retornos,
                           ROUND(100 * AVG(cf.codigo_convenio IS NULL), 1) AS pct_particulares,
                           (SELECT ROUND(AVG(t.n), 2)
                              FROM (SELECT COUNT(ct.codigo_medicamento) AS n
                                      FROM cf
                                      JOIN prescricao pr  ON pr.codigo_consulta = cf.codigo
                                      LEFT JOIN contem ct ON ct.codigo_consulta = pr.codigo_consulta
                                     GROUP BY cf.codigo) AS t)   AS medicamentos_por_receita,
                           (SELECT ROUND(AVG(t.n), 2)
                              FROM (SELECT COUNT(s.codigo_exame) AS n
                                      FROM cf
                                      LEFT JOIN solicita s ON s.codigo_consulta = cf.codigo
                                     GROUP BY cf.codigo) AS t)   AS exames_por_consulta,
                           ROUND(COUNT(*) / (PERIOD_DIFF(DATE_FORMAT(?, '%Y%m'),
                                                         DATE_FORMAT(?, '%Y%m')) + 1), 1) AS consultas_por_mes
                      FROM cf""";
            Map<String, Object> ind = new LinkedHashMap<>(umaLinha(con, f, kpi, sqls, "indicadores", f.fim, f.inicio));

            // tendência: mesmo filtro no período imediatamente anterior, de mesma duração
            LocalDate ini = LocalDate.parse(f.inicio);
            LocalDate fim = LocalDate.parse(f.fim);
            long dias = ChronoUnit.DAYS.between(ini, fim) + 1;
            LocalDate antFim = ini.minusDays(1);
            LocalDate antIni = antFim.minusDays(dias - 1);
            Filtro anterior = f.copiaComPeriodo(antIni.toString(), antFim.toString());
            Object antes = umaLinha(con, anterior, "SELECT COUNT(*) AS consultas FROM cf", null, null)
                    .get("consultas");
            ind.put("periodo_anterior", antIni + " a " + antFim);
            ind.put("consultas_periodo_anterior", antes);
            long agora = ((Number) ind.get("consultas")).longValue();
            long prev = ((Number) antes).longValue();
            ind.put("variacao_pct", prev == 0 ? null : Math.round(1000.0 * (agora - prev) / prev) / 10.0);
            d.put("indicadores", ind);

            // ------------------------------------------- série temporal (linha) + tendência
            String serie = """
                    meses AS (
                        SELECT CAST(DATE_FORMAT(?, '%Y-%m-01') AS DATE) AS mes
                        UNION ALL
                        SELECT mes + INTERVAL 1 MONTH FROM meses WHERE mes + INTERVAL 1 MONTH <= ?
                    ),
                    serie AS (
                        SELECT DATE_FORMAT(m.mes, '%Y-%m')         AS mes,
                               COUNT(cf.codigo)                    AS total,
                               COALESCE(SUM(cf.eh_retorno = 0), 0) AS primeiras,
                               COALESCE(SUM(cf.eh_retorno = 1), 0) AS retornos
                          FROM meses m
                          LEFT JOIN cf ON cf.data_consulta >= m.mes
                                      AND cf.data_consulta <  m.mes + INTERVAL 1 MONTH
                         GROUP BY m.mes
                    )""";
            String serieSelect = """
                    SELECT mes, primeiras, retornos, total,
                           ROUND(AVG(total) OVER (ORDER BY mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)
                               AS media_movel_3m
                      FROM serie
                     ORDER BY mes""";
            d.put("serieMensal", consultar(con, f, true, serie + "\n" + serieSelect, sqls, "serieMensal",
                    f.inicio, f.fim));
            d.put("tendencia", consultar(con, f, true, serie + ",\npares AS (SELECT ROW_NUMBER() OVER (ORDER BY mes) AS x,"
                    + " total AS y FROM serie)\n" + REGRESSAO, sqls, "tendencia", f.inicio, f.fim).get(0));

            // ------------------------------------------------------- categorias
            d.put("porEspecialidade", consultar(con, f, false, """
                    SELECT cf.especialidade AS rotulo, COUNT(*) AS valor
                      FROM cf
                     GROUP BY cf.especialidade
                     ORDER BY valor DESC, rotulo""", sqls, "porEspecialidade"));

            d.put("pagamento", consultar(con, f, false, """
                    SELECT CASE WHEN cf.codigo_convenio IS NULL THEN 'Particular' ELSE 'Convênio' END AS rotulo,
                           COUNT(*) AS valor
                      FROM cf
                     GROUP BY rotulo
                     ORDER BY valor DESC""", sqls, "pagamento"));

            d.put("diaSemana", consultar(con, f, false, """
                    SELECT ELT(WEEKDAY(cf.data_consulta) + 1, 'Segunda', 'Terça', 'Quarta', 'Quinta',
                               'Sexta', 'Sábado', 'Domingo') AS rotulo,
                           COUNT(*) AS valor
                      FROM cf
                     GROUP BY WEEKDAY(cf.data_consulta), rotulo
                     ORDER BY WEEKDAY(cf.data_consulta)""", sqls, "diaSemana"));

            d.put("polifarmacia", consultar(con, f, false, """
                    SELECT fn_classificar_polifarmacia(p.cpf_paciente) AS rotulo,
                           COUNT(*)                                     AS valor
                      FROM (SELECT DISTINCT cpf_paciente FROM cf) AS p
                     GROUP BY rotulo
                     ORDER BY valor DESC""", sqls, "polifarmacia"));

            d.put("topMedicamentos", consultar(con, f, false, """
                    SELECT med.nome AS rotulo, COUNT(*) AS valor
                      FROM cf
                      JOIN contem      ct  ON ct.codigo_consulta = cf.codigo
                      JOIN medicamento med ON med.codigo = ct.codigo_medicamento
                     GROUP BY med.nome
                     ORDER BY valor DESC, rotulo
                     LIMIT 10""", sqls, "topMedicamentos"));

            d.put("topExames", consultar(con, f, false, """
                    SELECT e.nome AS rotulo, COUNT(*) AS valor
                      FROM cf
                      JOIN solicita s ON s.codigo_consulta = cf.codigo
                      JOIN exame    e ON e.codigo = s.codigo_exame
                     GROUP BY e.nome
                     ORDER BY valor DESC, rotulo
                     LIMIT 10""", sqls, "topExames"));

            d.put("radar", consultar(con, f, false, """
                    SELECT cf.especialidade,
                           COUNT(*)                                  AS consultas,
                           COUNT(DISTINCT cf.cpf_paciente)           AS pacientes,
                           ROUND(100 * AVG(cf.eh_retorno), 1)        AS pct_retornos,
                           ROUND(AVG((SELECT COUNT(*) FROM contem ct
                                       WHERE ct.codigo_consulta = cf.codigo)), 2) AS medicamentos_por_consulta,
                           ROUND(AVG((SELECT COUNT(*) FROM solicita s
                                       WHERE s.codigo_consulta = cf.codigo)), 2)  AS exames_por_consulta
                      FROM cf
                     GROUP BY cf.especialidade
                     ORDER BY consultas DESC, cf.especialidade""", sqls, "radar"));

            // ---------------------------------------------- correlação (dispersão)
            String pares = """
                    pares AS (
                        SELECT cf.cpf_paciente,
                               COUNT(DISTINCT cf.codigo)              AS x,   -- consultas do paciente
                               COUNT(DISTINCT ct.codigo_medicamento)  AS y    -- medicamentos distintos
                          FROM cf
                          LEFT JOIN contem ct ON ct.codigo_consulta = cf.codigo
                         GROUP BY cf.cpf_paciente
                    )""";
            Map<String, Object> disp = new LinkedHashMap<>();
            disp.put("pontos", consultar(con, f, false, pares + """

                    SELECT x, y, COUNT(*) AS pacientes
                      FROM pares
                     GROUP BY x, y
                     ORDER BY x, y""", sqls, "dispersao"));
            disp.putAll(consultar(con, f, false, pares + "\n" + REGRESSAO, sqls, "correlacao").get(0));
            d.put("dispersao", disp);

            // ------------------------------------------------ estatística descritiva
            List<Map<String, Object>> estat = new ArrayList<>();
            for (Variavel v : VARIAVEIS) {
                String cteV = "v AS (\n" + v.sql() + "\n)";
                Map<String, Object> e = new LinkedHashMap<>();
                e.put("id", v.id());
                e.put("rotulo", v.rotulo());
                e.put("unidade", v.unidade());
                e.put("largura", v.largura());
                e.putAll(consultar(con, f, false, cteV + "\n" + ESTATISTICAS, sqls, "estat_" + v.id()).get(0));
                e.put("frequencias", consultar(con, f, false, cteV + "\n" + FREQUENCIAS, sqls,
                        "freq_" + v.id(), v.largura(), v.largura()));
                estat.add(e);
            }
            d.put("estatisticas", estat);
        }
        d.put("sql", sqls);
        return d;
    }

    /**
     * Monta "WITH [RECURSIVE] cf AS (...), <corpo>" e executa.
     * corpo: ou começa com outras CTEs ("x AS (...) SELECT ...") ou é direto o SELECT.
     */
    private static List<Map<String, Object>> consultar(Connection con, Filtro f, boolean recursivo, String corpo,
                                                       Map<String, String> sqls, String chave,
                                                       Object... extras) throws SQLException {
        List<Object> params = new ArrayList<>();
        String cte = f.cte(params);
        boolean temOutrasCtes = !corpo.stripLeading().toUpperCase().startsWith("SELECT");
        String sql = "WITH " + (recursivo ? "RECURSIVE " : "") + cte + (temOutrasCtes ? ",\n" : "\n") + corpo;
        params.addAll(List.of(extras));
        if (sqls != null) {
            sqls.put(chave, sql);
        }
        return Database.lista(con, sql, params);
    }

    private static Map<String, Object> umaLinha(Connection con, Filtro f, String select,
                                                Map<String, String> sqls, String chave,
                                                Object... extras) throws SQLException {
        return consultar(con, f, false, select, sqls, chave, extras).get(0);
    }

    private static String vazioNulo(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}

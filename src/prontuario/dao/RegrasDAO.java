package prontuario.dao;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/**
 * Integração da interface com os objetos da Etapa 05:
 *   funções      fn_classificar_polifarmacia, fn_paciente_alergico_a_medicamento
 *   procedimentos sp_atualizar_convenio_paciente, sp_agendar_pacientes_sem_consulta (cursor)
 *   triggers     trg_contem_bloqueia_alergia, trg_paciente_log_convenio (log_auditoria)
 */
public class RegrasDAO {

    // ------------------------------------------------------------------ funções

    public Map<String, Object> polifarmacia(String classe) throws SQLException {
        String sql = """
                SELECT pac.numero_prontuario                  AS prontuario,
                       p.nome                                 AS paciente,
                       (SELECT COUNT(DISTINCT ct.codigo_medicamento)
                          FROM consulta c
                          JOIN contem ct ON ct.codigo_consulta = c.codigo
                         WHERE c.cpf_paciente = pac.cpf)      AS medicamentos_distintos,
                       fn_classificar_polifarmacia(pac.cpf)   AS classificacao
                  FROM paciente pac
                  JOIN pessoa p ON p.cpf = pac.cpf
                 WHERE (? IS NULL OR fn_classificar_polifarmacia(pac.cpf) = ?)
                 ORDER BY medicamentos_distintos DESC, p.nome""";
        String sqlResumo = """
                SELECT fn_classificar_polifarmacia(pac.cpf) AS rotulo,
                       COUNT(*)                             AS valor
                  FROM paciente pac
                 GROUP BY rotulo
                 ORDER BY valor DESC""";
        Map<String, Object> r = new LinkedHashMap<>();
        try (Connection con = Database.getConnection()) {
            r.put("sql", sql);
            r.put("pacientes", Database.lista(con, sql, java.util.Arrays.asList(classe, classe)));
            r.put("resumo", Database.lista(con, sqlResumo, List.of()));
        }
        return r;
    }

    public Map<String, Object> verificarAlergia(String cpf, int codigoMedicamento) throws SQLException {
        String sql = """
                SELECT fn_paciente_alergico_a_medicamento(?, ?)          AS conflito,
                       (SELECT nome FROM pessoa WHERE cpf = ?)           AS paciente,
                       (SELECT nome FROM medicamento WHERE codigo = ?)   AS medicamento,
                       (SELECT GROUP_CONCAT(alergia ORDER BY alergia SEPARATOR ', ')
                          FROM alergia WHERE cpf = ?)                     AS alergias""";
        Map<String, Object> r = new LinkedHashMap<>(
                Database.lista(sql, cpf, codigoMedicamento, cpf, codigoMedicamento, cpf).get(0));
        r.put("sql", "SELECT fn_paciente_alergico_a_medicamento('" + cpf + "', " + codigoMedicamento + ");");
        return r;
    }

    /** Auditoria: itens de receita JÁ gravados (antes do trigger existir) que a função acusa como conflito. */
    public Map<String, Object> conflitosGravados() throws SQLException {
        String sql = """
                SELECT c.codigo          AS consulta,
                       c.data_consulta   AS data,
                       p.nome            AS paciente,
                       med.nome          AS medicamento,
                       (SELECT GROUP_CONCAT(a.alergia ORDER BY a.alergia SEPARATOR ', ')
                          FROM alergia a WHERE a.cpf = c.cpf_paciente) AS alergias_do_paciente
                  FROM contem ct
                  JOIN consulta    c   ON c.codigo   = ct.codigo_consulta
                  JOIN pessoa      p   ON p.cpf      = c.cpf_paciente
                  JOIN medicamento med ON med.codigo = ct.codigo_medicamento
                 WHERE fn_paciente_alergico_a_medicamento(c.cpf_paciente, ct.codigo_medicamento) = 1
                 ORDER BY c.data_consulta, c.codigo""";
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("sql", sql);
        r.put("linhas", Database.lista(sql));
        return r;
    }

    // ------------------------------------------------------------ procedimentos

    /** CALL sp_atualizar_convenio_paciente(cpf, convenio) — o UPDATE dispara trg_paciente_log_convenio. */
    public Map<String, Object> atualizarConvenio(String cpf, Integer codigoConvenio) throws SQLException {
        Map<String, Object> r = new LinkedHashMap<>();
        try (Connection con = Database.getConnection();
             CallableStatement cs = con.prepareCall("{CALL sp_atualizar_convenio_paciente(?, ?)}")) {
            cs.setString(1, cpf);
            if (codigoConvenio == null) {
                cs.setNull(2, Types.INTEGER);
            } else {
                cs.setInt(2, codigoConvenio);
            }
            boolean temResultado = cs.execute();
            if (temResultado) {
                try (ResultSet rs = cs.getResultSet()) {
                    if (rs.next()) {
                        Map<String, Object> linha = new LinkedHashMap<>();
                        linha.put("prontuario", rs.getObject("prontuario"));
                        linha.put("paciente", rs.getObject("paciente"));
                        linha.put("convenio_atual", rs.getObject("convenio_atual"));
                        r.put("cadastro", linha);
                    }
                }
            }
            r.put("log", Database.lista(con, "SELECT * FROM log_auditoria ORDER BY codigo DESC LIMIT 1", List.of()));
        }
        r.put("sql", "CALL sp_atualizar_convenio_paciente('" + cpf + "', "
                + (codigoConvenio == null ? "NULL" : codigoConvenio) + ");");
        return r;
    }

    public List<Map<String, Object>> pacientesSemConsulta() throws SQLException {
        return Database.lista("""
                SELECT pac.numero_prontuario AS prontuario, p.nome AS paciente,
                       COALESCE(cv.nome, 'Particular') AS convenio
                  FROM paciente pac
                  JOIN pessoa p         ON p.cpf     = pac.cpf
                  LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
                 WHERE NOT EXISTS (SELECT 1 FROM consulta c WHERE c.cpf_paciente = pac.cpf)
                 ORDER BY pac.numero_prontuario""");
    }

    /**
     * CALL sp_agendar_pacientes_sem_consulta(@total) dentro de uma transação.
     * confirmar = false -> ROLLBACK no fim (simulação: mostra o que o cursor faria e desfaz).
     */
    public Map<String, Object> agendar(boolean confirmar) throws SQLException {
        Map<String, Object> r = new LinkedHashMap<>();
        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try {
                int ultimoCodigo;
                try (PreparedStatement ps = con.prepareStatement("SELECT COALESCE(MAX(codigo), 0) FROM consulta");
                     ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    ultimoCodigo = rs.getInt(1);
                }
                int total;
                try (CallableStatement cs = con.prepareCall("{CALL sp_agendar_pacientes_sem_consulta(?)}")) {
                    cs.registerOutParameter(1, Types.INTEGER);
                    cs.execute();
                    total = cs.getInt(1);
                }
                List<Map<String, Object>> criadas = Database.lista(con, """
                        SELECT c.codigo, c.data_consulta, pp.nome AS paciente, pm.nome AS medico,
                               m.especialidade,
                               (SELECT COUNT(*) FROM consulta c2 WHERE c2.cpf_medico = c.cpf_medico)
                                   AS consultas_do_medico_agora
                          FROM consulta c
                          JOIN pessoa pp ON pp.cpf = c.cpf_paciente
                          JOIN medico m  ON m.cpf  = c.cpf_medico
                          JOIN pessoa pm ON pm.cpf = m.cpf
                         WHERE c.codigo > ?
                         ORDER BY c.codigo""", List.of(ultimoCodigo));
                if (confirmar) {
                    con.commit();
                } else {
                    con.rollback();
                }
                r.put("total", total);
                r.put("confirmado", confirmar);
                r.put("consultas", criadas);
                r.put("sql", "START TRANSACTION;\nCALL sp_agendar_pacientes_sem_consulta(@total);\nSELECT @total;\n"
                        + (confirmar ? "COMMIT;" : "ROLLBACK;  -- simulação"));
            } catch (SQLException e) {
                con.rollback();
                throw e;
            }
        }
        return r;
    }

    // ----------------------------------------------------------------- triggers

    /**
     * Tenta gravar o item de receita para ver o trigger trg_contem_bloqueia_alergia agir.
     * Sempre desfaz no fim (é só um teste); para prescrever de verdade use a tela de consultas.
     */
    public Map<String, Object> testarTriggerAlergia(int codigoConsulta, int codigoMedicamento) throws SQLException {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("sql", "START TRANSACTION;\nINSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES ("
                + codigoConsulta + ", " + codigoMedicamento + ");\nROLLBACK;  -- teste");
        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES (?, ?)")) {
                ps.setInt(1, codigoConsulta);
                ps.setInt(2, codigoMedicamento);
                ps.executeUpdate();
                r.put("bloqueado", false);
                r.put("mensagem", "Inserção aceita pelo banco (nenhum conflito de alergia). Desfeita com ROLLBACK.");
            } catch (SQLException e) {
                if (e.getErrorCode() == 1644) {
                    r.put("bloqueado", true);
                    r.put("mensagem", e.getMessage());
                } else {
                    throw e;
                }
            } finally {
                con.rollback();
            }
        }
        return r;
    }

    public List<Map<String, Object>> consultasComReceita() throws SQLException {
        return Database.lista("""
                SELECT c.codigo, c.data_consulta, p.nome AS paciente,
                       (SELECT GROUP_CONCAT(a.alergia ORDER BY a.alergia SEPARATOR ', ')
                          FROM alergia a WHERE a.cpf = c.cpf_paciente) AS alergias
                  FROM consulta c
                  JOIN prescricao pr ON pr.codigo_consulta = c.codigo
                  JOIN pessoa p      ON p.cpf = c.cpf_paciente
                 ORDER BY c.codigo""");
    }

    public List<Map<String, Object>> log() throws SQLException {
        return Database.lista("""
                SELECT l.codigo, l.data_hora, l.tabela, l.operacao, l.chave,
                       p.nome AS paciente, l.detalhe, l.usuario
                  FROM log_auditoria l
                  LEFT JOIN pessoa p ON p.cpf = l.chave
                 ORDER BY l.codigo DESC
                 LIMIT 200""");
    }

    /** Código dos objetos como estão gravados no servidor (information_schema). */
    public List<Map<String, Object>> objetos() throws SQLException {
        List<Map<String, Object>> lista = new ArrayList<>();
        lista.addAll(Database.lista("""
                SELECT ROUTINE_TYPE AS tipo, ROUTINE_NAME AS nome, ROUTINE_DEFINITION AS definicao
                  FROM information_schema.ROUTINES
                 WHERE ROUTINE_SCHEMA = DATABASE()
                 ORDER BY ROUTINE_TYPE, ROUTINE_NAME"""));
        lista.addAll(Database.lista("""
                SELECT 'TRIGGER' AS tipo, TRIGGER_NAME AS nome,
                       CONCAT(ACTION_TIMING, ' ', EVENT_MANIPULATION, ' ON ', EVENT_OBJECT_TABLE,
                              ' FOR EACH ROW\\n', ACTION_STATEMENT) AS definicao
                  FROM information_schema.TRIGGERS
                 WHERE TRIGGER_SCHEMA = DATABASE()
                 ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME"""));
        return lista;
    }
}

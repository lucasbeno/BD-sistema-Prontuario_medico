package prontuario.dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/**
 * CRUD da tabela consulta e das tabelas que dependem dela:
 * retorno (auto-relacionamento), prescricao (receita), contem (itens da receita)
 * e solicita (exames pedidos).
 */
public class ConsultaDAO {

    public List<Map<String, Object>> listar(String inicio, String fim) throws SQLException {
        String sql = """
                SELECT c.codigo,
                       c.data_consulta,
                       CASE WHEN r.codigo_consulta_origem IS NULL THEN 'Primeira consulta'
                            ELSE 'Retorno' END                       AS tipo,
                       r.codigo_consulta_origem                      AS retorno_de,
                       c.cpf_paciente,
                       pp.nome                                       AS paciente,
                       c.cpf_medico,
                       pm.nome                                       AS medico,
                       m.especialidade,
                       pr.numero                                     AS numero_receita,
                       (SELECT COUNT(*) FROM contem ct
                         WHERE ct.codigo_consulta = c.codigo)        AS medicamentos,
                       (SELECT COUNT(*) FROM solicita s
                         WHERE s.codigo_consulta = c.codigo)         AS exames
                  FROM consulta c
                  JOIN pessoa pp          ON pp.cpf = c.cpf_paciente
                  JOIN medico m           ON m.cpf  = c.cpf_medico
                  JOIN pessoa pm          ON pm.cpf = m.cpf
                  LEFT JOIN retorno r     ON r.codigo_consulta_retorno = c.codigo
                  LEFT JOIN prescricao pr ON pr.codigo_consulta = c.codigo
                 WHERE c.data_consulta BETWEEN COALESCE(?, '1900-01-01') AND COALESCE(?, '9999-12-31')
                 ORDER BY c.data_consulta DESC, c.codigo DESC
                """;
        return Database.lista(sql, inicio, fim);
    }

    /** Detalhe de uma consulta: dados + receita + medicamentos + exames + alergias do paciente. */
    public Map<String, Object> detalhar(int codigo) throws SQLException {
        try (Connection con = Database.getConnection()) {
            List<Map<String, Object>> cab = Database.lista(con, """
                    SELECT c.codigo, c.data_consulta, c.cpf_paciente, pp.nome AS paciente,
                           c.cpf_medico, pm.nome AS medico, m.especialidade,
                           r.codigo_consulta_origem AS retorno_de,
                           pr.numero AS numero_receita, pr.nome AS nome_receita
                      FROM consulta c
                      JOIN pessoa pp          ON pp.cpf = c.cpf_paciente
                      JOIN medico m           ON m.cpf  = c.cpf_medico
                      JOIN pessoa pm          ON pm.cpf = m.cpf
                      LEFT JOIN retorno r     ON r.codigo_consulta_retorno = c.codigo
                      LEFT JOIN prescricao pr ON pr.codigo_consulta = c.codigo
                     WHERE c.codigo = ?
                    """, List.of(codigo));
            if (cab.isEmpty()) {
                return null;
            }
            Map<String, Object> d = new LinkedHashMap<>(cab.get(0));
            d.put("medicamentos", Database.lista(con, """
                    SELECT med.codigo, med.nome
                      FROM contem ct
                      JOIN medicamento med ON med.codigo = ct.codigo_medicamento
                     WHERE ct.codigo_consulta = ?
                     ORDER BY med.nome
                    """, List.of(codigo)));
            d.put("exames", Database.lista(con, """
                    SELECT e.codigo, e.nome
                      FROM solicita s
                      JOIN exame e ON e.codigo = s.codigo_exame
                     WHERE s.codigo_consulta = ?
                     ORDER BY e.nome
                    """, List.of(codigo)));
            d.put("alergias", Database.lista(con, """
                    SELECT a.alergia
                      FROM consulta c
                      JOIN alergia a ON a.cpf = c.cpf_paciente
                     WHERE c.codigo = ?
                     ORDER BY a.alergia
                    """, List.of(codigo)));
            return d;
        }
    }

    /**
     * Cadastra a consulta (e, se informado, o vínculo de retorno e a receita) numa transação só.
     * Os triggers trg_consulta_pessoas_ins e trg_retorno_distinta_ins validam os dados.
     */
    public int inserir(String cpfPaciente, String cpfMedico, String data, Integer retornoDe,
                       String nomeReceita) throws SQLException {
        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try {
                int codigo;
                try (PreparedStatement ps = con.prepareStatement(
                        "INSERT INTO consulta (cpf_paciente, cpf_medico, data_consulta) "
                                + "VALUES (?, ?, COALESCE(?, CURRENT_DATE))",
                        Statement.RETURN_GENERATED_KEYS)) {
                    ps.setString(1, cpfPaciente);
                    ps.setString(2, cpfMedico);
                    ps.setString(3, data);
                    ps.executeUpdate();
                    try (ResultSet rs = ps.getGeneratedKeys()) {
                        rs.next();
                        codigo = rs.getInt(1);
                    }
                }
                if (retornoDe != null) {
                    try (PreparedStatement ps = con.prepareStatement(
                            "INSERT INTO retorno (codigo_consulta_origem, codigo_consulta_retorno) VALUES (?, ?)")) {
                        ps.setInt(1, retornoDe);
                        ps.setInt(2, codigo);
                        ps.executeUpdate();
                    }
                }
                if (nomeReceita != null) {
                    inserirReceita(con, codigo, nomeReceita);
                }
                con.commit();
                return codigo;
            } catch (SQLException e) {
                con.rollback();
                throw e;
            }
        }
    }

    public int alterar(int codigo, String cpfPaciente, String cpfMedico, String data) throws SQLException {
        return Database.executar("""
                UPDATE consulta
                   SET cpf_paciente = ?, cpf_medico = ?, data_consulta = COALESCE(?, data_consulta)
                 WHERE codigo = ?
                """, cpfPaciente, cpfMedico, data, codigo);
    }

    /** ON DELETE CASCADE: apaga junto receita, itens, exames e vínculos de retorno. */
    public int excluir(int codigo) throws SQLException {
        return Database.executar("DELETE FROM consulta WHERE codigo = ?", codigo);
    }

    public void criarReceita(int codigo, String nome) throws SQLException {
        try (Connection con = Database.getConnection()) {
            inserirReceita(con, codigo, nome);
        }
    }

    private static void inserirReceita(Connection con, int codigo, String nome) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(
                "INSERT INTO prescricao (codigo_consulta, nome) VALUES (?, COALESCE(?, DEFAULT(nome)))")) {
            ps.setInt(1, codigo);
            ps.setString(2, nome == null || nome.isBlank() ? null : nome);
            ps.executeUpdate();
        }
    }

    public int excluirReceita(int codigo) throws SQLException {
        return Database.executar("DELETE FROM prescricao WHERE codigo_consulta = ?", codigo);
    }

    /** Dispara o trigger trg_contem_bloqueia_alergia (BEFORE INSERT em contem). */
    public void prescrever(int codigo, int codigoMedicamento) throws SQLException {
        Database.executar("INSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES (?, ?)",
                codigo, codigoMedicamento);
    }

    public int removerMedicamento(int codigo, int codigoMedicamento) throws SQLException {
        return Database.executar("DELETE FROM contem WHERE codigo_consulta = ? AND codigo_medicamento = ?",
                codigo, codigoMedicamento);
    }

    public void solicitarExame(int codigo, int codigoExame) throws SQLException {
        Database.executar("INSERT INTO solicita (codigo_consulta, codigo_exame) VALUES (?, ?)", codigo, codigoExame);
    }

    public int removerExame(int codigo, int codigoExame) throws SQLException {
        return Database.executar("DELETE FROM solicita WHERE codigo_consulta = ? AND codigo_exame = ?",
                codigo, codigoExame);
    }

    /** Lista curta para os campos de seleção ("retorno da consulta nº"). */
    public List<Map<String, Object>> opcoes() throws SQLException {
        return Database.lista("""
                SELECT c.codigo, c.data_consulta, p.nome AS paciente, c.cpf_paciente
                  FROM consulta c JOIN pessoa p ON p.cpf = c.cpf_paciente
                 ORDER BY c.codigo DESC
                """);
    }
}

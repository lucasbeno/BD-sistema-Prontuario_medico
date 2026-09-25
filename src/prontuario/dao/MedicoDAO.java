package prontuario.dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import prontuario.Database;

public class MedicoDAO {
    public List<Map<String, Object>> listar() throws SQLException {
        String sql = """
                SELECT p.cpf,
                       p.nome,
                       p.cep,
                       p.numero_apto,
                       m.crm,
                       m.especialidade,
                       (SELECT COUNT(*) FROM consulta c WHERE c.cpf_medico = m.cpf) AS total_consultas
                  FROM medico m
                  JOIN pessoa p ON p.cpf = m.cpf
                 ORDER BY p.nome
                """;
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            return Database.paraLista(ps);
        }
    }

    public void inserir(String cpf, String nome, String cep, String numeroApto,
                        String crm, String especialidade) throws SQLException {
        String sqlPessoa = "INSERT INTO pessoa (cpf, nome, cep, numero_apto) VALUES (?, ?, ?, COALESCE(?, DEFAULT(numero_apto)))";
        String sqlMedico = "INSERT INTO medico (cpf, crm, especialidade) VALUES (?, ?, COALESCE(?, DEFAULT(especialidade)))";

        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try {
                try (PreparedStatement ps = con.prepareStatement(sqlPessoa)) {
                    ps.setString(1, cpf);
                    ps.setString(2, nome);
                    ps.setString(3, cep);
                    ps.setString(4, numeroApto);
                    ps.executeUpdate();
                }
                try (PreparedStatement ps = con.prepareStatement(sqlMedico)) {
                    ps.setString(1, cpf);
                    ps.setString(2, crm);
                    ps.setString(3, especialidade);
                    ps.executeUpdate();
                }
                con.commit();
            } catch (SQLException e) {
                con.rollback();
                throw e;
            }
        }
    }

    public int alterar(String cpfAtual, String novoCpf, String nome, String cep, String numeroApto,
                       String crm, String especialidade) throws SQLException {
        String sqlMedico = """
                UPDATE medico
                   SET crm = ?, especialidade = COALESCE(?, DEFAULT(especialidade))
                 WHERE cpf = ?
                """;
        String sqlPessoa = """
                UPDATE pessoa
                   SET cpf = ?, nome = ?, cep = ?, numero_apto = COALESCE(?, DEFAULT(numero_apto))
                 WHERE cpf = ?
                """;
        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try {
                int linhas;
                try (PreparedStatement ps = con.prepareStatement(sqlMedico)) {
                    ps.setString(1, crm);
                    ps.setString(2, especialidade);
                    ps.setString(3, cpfAtual);
                    linhas = ps.executeUpdate();
                }
                try (PreparedStatement ps = con.prepareStatement(sqlPessoa)) {
                    ps.setString(1, novoCpf);
                    ps.setString(2, nome);
                    ps.setString(3, cep);
                    ps.setString(4, numeroApto);
                    ps.setString(5, cpfAtual);
                    ps.executeUpdate();
                }
                con.commit();
                return linhas;
            } catch (SQLException e) {
                con.rollback();
                throw e;
            }
        }
    }

    public int excluir(String cpf) throws SQLException {
        String sql = "DELETE FROM pessoa WHERE cpf = ? AND cpf IN (SELECT cpf FROM medico)";
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, cpf);
            return ps.executeUpdate();
        }
    }
}

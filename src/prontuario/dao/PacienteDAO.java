package prontuario.dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Types;
import java.util.List;
import java.util.Map;

import prontuario.Database;

public class PacienteDAO {
    public List<Map<String, Object>> listar() throws SQLException {
        String sql = """
                SELECT p.cpf,
                       p.nome,
                       p.cep,
                       p.numero_apto,
                       pac.numero_prontuario,
                       pac.codigo_convenio,
                       COALESCE(cv.nome, 'Particular') AS convenio,
                       (SELECT GROUP_CONCAT(t.telefone ORDER BY t.telefone SEPARATOR ', ')
                          FROM telefone t
                         WHERE t.cpf = p.cpf) AS telefones
                  FROM paciente pac
                  JOIN pessoa p        ON p.cpf = pac.cpf
                  LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
                 ORDER BY pac.numero_prontuario
                """;
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            return Database.paraLista(ps);
        }
    }

    public void inserir(String cpf, String nome, String cep, String numeroApto,
                        Integer codigoConvenio, String telefone) throws SQLException {
        String sqlPessoa = "INSERT INTO pessoa (cpf, nome, cep, numero_apto) VALUES (?, ?, ?, COALESCE(?, DEFAULT(numero_apto)))";
        String sqlPaciente = "INSERT INTO paciente (cpf, codigo_convenio) VALUES (?, ?)";
        String sqlTelefone = "INSERT INTO telefone (cpf, telefone) VALUES (?, ?)";

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
                try (PreparedStatement ps = con.prepareStatement(sqlPaciente)) {
                    ps.setString(1, cpf);
                    setIntegerOuNull(ps, 2, codigoConvenio);
                    ps.executeUpdate();
                }
                if (telefone != null) {
                    try (PreparedStatement ps = con.prepareStatement(sqlTelefone)) {
                        ps.setString(1, cpf);
                        ps.setString(2, telefone);
                        ps.executeUpdate();
                    }
                }
                con.commit();
            } catch (SQLException e) {
                con.rollback();
                throw e;
            }
        }
    }

    public int alterar(String cpfAtual, String novoCpf, String nome, String cep, String numeroApto,
                       Integer codigoConvenio) throws SQLException {
        String sqlConvenio = "UPDATE paciente SET codigo_convenio = ? WHERE cpf = ?";
        String sqlPessoa = """
                UPDATE pessoa
                   SET cpf = ?, nome = ?, cep = ?, numero_apto = COALESCE(?, DEFAULT(numero_apto))
                 WHERE cpf = ?
                """;
        try (Connection con = Database.getConnection()) {
            con.setAutoCommit(false);
            try {
                int linhas;
                try (PreparedStatement ps = con.prepareStatement(sqlConvenio)) {
                    setIntegerOuNull(ps, 1, codigoConvenio);
                    ps.setString(2, cpfAtual);
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
        String sql = "DELETE FROM pessoa WHERE cpf = ? AND cpf IN (SELECT cpf FROM paciente)";
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, cpf);
            return ps.executeUpdate();
        }
    }

    static void setIntegerOuNull(PreparedStatement ps, int indice, Integer valor) throws SQLException {
        if (valor == null) {
            ps.setNull(indice, Types.INTEGER);
        } else {
            ps.setInt(indice, valor);
        }
    }
}

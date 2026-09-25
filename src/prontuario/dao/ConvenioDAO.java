package prontuario.dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import prontuario.Database;

public class ConvenioDAO {
    public List<Map<String, Object>> listar() throws SQLException {
        String sql = """
                SELECT cv.codigo,
                       cv.nome,
                       COUNT(pac.cpf) AS total_pacientes
                  FROM convenio cv
                  LEFT JOIN paciente pac ON pac.codigo_convenio = cv.codigo
                 GROUP BY cv.codigo, cv.nome
                 ORDER BY cv.codigo
                """;
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            return Database.paraLista(ps);
        }
    }

    public void inserir(String nome) throws SQLException {
        String sql = "INSERT INTO convenio (nome) VALUES (?)";
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, nome);
            ps.executeUpdate();
        }
    }

    public int alterar(int codigoAtual, int novoCodigo, String nome) throws SQLException {
        String sql = "UPDATE convenio SET codigo = ?, nome = ? WHERE codigo = ?";
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, novoCodigo);
            ps.setString(2, nome);
            ps.setInt(3, codigoAtual);
            return ps.executeUpdate();
        }
    }

    public int excluir(int codigo) throws SQLException {
        String sql = "DELETE FROM convenio WHERE codigo = ?";
        try (Connection con = Database.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, codigo);
            return ps.executeUpdate();
        }
    }
}

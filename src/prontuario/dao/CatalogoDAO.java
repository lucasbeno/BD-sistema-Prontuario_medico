package prontuario.dao;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/**
 * CRUD das tabelas de catálogo medicamento e exame. As duas têm a mesma forma
 * (codigo AUTO_INCREMENT + nome UNIQUE) e são usadas por uma tabela associativa
 * (contem / solicita) com ON DELETE RESTRICT e ON UPDATE CASCADE.
 */
public class CatalogoDAO {
    private final String tabela;
    private final String associativa;
    private final String colunaFk;

    private CatalogoDAO(String tabela, String associativa, String colunaFk) {
        this.tabela = tabela;
        this.associativa = associativa;
        this.colunaFk = colunaFk;
    }

    public static CatalogoDAO medicamentos() {
        return new CatalogoDAO("medicamento", "contem", "codigo_medicamento");
    }

    public static CatalogoDAO exames() {
        return new CatalogoDAO("exame", "solicita", "codigo_exame");
    }

    public List<Map<String, Object>> listar() throws SQLException {
        String sql = "SELECT t.codigo, t.nome, COUNT(a." + colunaFk + ") AS vezes_usado"
                + "  FROM " + tabela + " t"
                + "  LEFT JOIN " + associativa + " a ON a." + colunaFk + " = t.codigo"
                + " GROUP BY t.codigo, t.nome"
                + " ORDER BY t.nome";
        return Database.lista(sql);
    }

    public void inserir(String nome) throws SQLException {
        Database.executar("INSERT INTO " + tabela + " (nome) VALUES (?)", nome);
    }

    public int alterar(int codigoAtual, int novoCodigo, String nome) throws SQLException {
        return Database.executar("UPDATE " + tabela + " SET codigo = ?, nome = ? WHERE codigo = ?",
                novoCodigo, nome, codigoAtual);
    }

    public int excluir(int codigo) throws SQLException {
        return Database.executar("DELETE FROM " + tabela + " WHERE codigo = ?", codigo);
    }
}

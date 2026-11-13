package prontuario.dao;

import java.sql.SQLException;
import java.util.List;
import java.util.Map;

import prontuario.Database;

/** Alergias de um paciente (atributo multivalorado -> tabela alergia). */
public class AlergiaDAO {
    public List<Map<String, Object>> listar(String cpf) throws SQLException {
        return Database.lista("SELECT alergia FROM alergia WHERE cpf = ? ORDER BY alergia", cpf);
    }

    public void inserir(String cpf, String alergia) throws SQLException {
        Database.executar("INSERT INTO alergia (cpf, alergia) VALUES (?, ?)", cpf, alergia);
    }

    public int alterar(String cpf, String alergiaAtual, String novaAlergia) throws SQLException {
        return Database.executar("UPDATE alergia SET alergia = ? WHERE cpf = ? AND alergia = ?",
                novaAlergia, cpf, alergiaAtual);
    }

    public int excluir(String cpf, String alergia) throws SQLException {
        return Database.executar("DELETE FROM alergia WHERE cpf = ? AND alergia = ?", cpf, alergia);
    }
}

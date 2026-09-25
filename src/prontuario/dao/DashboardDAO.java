package prontuario.dao;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import prontuario.Database;

public class DashboardDAO {
    public Map<String, Object> carregar() throws SQLException {
        Map<String, Object> dados = new LinkedHashMap<>();
        try (Connection con = Database.getConnection()) {
            dados.put("indicadores", umaLinha(con, """
                    SELECT
                        (SELECT COUNT(*) FROM paciente)  AS pacientes,
                        (SELECT COUNT(*) FROM medico)    AS medicos,
                        (SELECT COUNT(*) FROM consulta)  AS consultas,
                        (SELECT COUNT(*) FROM retorno)   AS retornos,
                        ROUND(100 * (SELECT COUNT(*) FROM paciente WHERE codigo_convenio IS NULL)
                                  / (SELECT COUNT(*) FROM paciente), 1) AS pct_particulares,
                        ROUND((SELECT COUNT(*) FROM contem) / (SELECT COUNT(*) FROM prescricao), 2)
                                                         AS media_medicamentos_por_receita
                    """));

            dados.put("consultasPorEspecialidade", lista(con, """
                    SELECT m.especialidade AS rotulo, COUNT(*) AS valor
                    FROM consulta c
                    JOIN medico m ON m.cpf = c.cpf_medico
                    GROUP BY m.especialidade
                    ORDER BY valor DESC, rotulo
                    """));

            dados.put("pacientesComSemConvenio", lista(con, """
                    SELECT CASE WHEN codigo_convenio IS NULL THEN 'Particular' ELSE 'Com convênio' END AS rotulo,
                           COUNT(*) AS valor
                    FROM paciente
                    GROUP BY rotulo
                    ORDER BY valor DESC
                    """));

            dados.put("topMedicamentos", lista(con, """
                    SELECT med.nome AS rotulo, COUNT(*) AS valor
                    FROM contem ct
                    JOIN medicamento med ON med.codigo = ct.codigo_medicamento
                    GROUP BY med.nome
                    ORDER BY valor DESC, rotulo
                    LIMIT 10
                    """));

            dados.put("topExames", lista(con, """
                    SELECT e.nome AS rotulo, COUNT(*) AS valor
                    FROM solicita s
                    JOIN exame e ON e.codigo = s.codigo_exame
                    GROUP BY e.nome
                    ORDER BY valor DESC, rotulo
                    LIMIT 10
                    """));

            dados.put("distribuicaoConsultasPorPaciente", lista(con, """
                    SELECT qtd AS rotulo, COUNT(*) AS valor
                    FROM (
                        SELECT pac.cpf, COUNT(c.codigo) AS qtd
                        FROM paciente pac
                        LEFT JOIN consulta c ON c.cpf_paciente = pac.cpf
                        GROUP BY pac.cpf
                    ) t
                    GROUP BY qtd
                    ORDER BY qtd
                    """));

            dados.put("distribuicaoAlergias", lista(con, """
                    SELECT qtd AS rotulo, COUNT(*) AS valor
                    FROM (
                        SELECT pac.cpf, COUNT(a.alergia) AS qtd
                        FROM paciente pac
                        LEFT JOIN alergia a ON a.cpf = pac.cpf
                        GROUP BY pac.cpf
                    ) t
                    GROUP BY qtd
                    ORDER BY qtd
                    """));
        }
        return dados;
    }

    private static List<Map<String, Object>> lista(Connection con, String sql) throws SQLException {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            return Database.paraLista(ps);
        }
    }

    private static Map<String, Object> umaLinha(Connection con, String sql) throws SQLException {
        return lista(con, sql).get(0);
    }
}

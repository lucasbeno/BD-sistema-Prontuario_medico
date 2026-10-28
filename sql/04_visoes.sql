USE prontuario_medico;

CREATE OR REPLACE VIEW vw_prontuario_paciente AS
SELECT
    pac.numero_prontuario                                    AS prontuario,
    pac.cpf                                                  AS cpf,
    p.nome                                                   AS paciente,
    COALESCE(cv.nome, 'Particular')                          AS convenio,
    GROUP_CONCAT(DISTINCT tel.telefone
                 ORDER BY tel.telefone SEPARATOR ', ')       AS telefones,
    GROUP_CONCAT(DISTINCT a.alergia
                 ORDER BY a.alergia SEPARATOR ', ')          AS alergias,
    COUNT(DISTINCT c.codigo)                                 AS total_consultas,
    GROUP_CONCAT(DISTINCT CONCAT(pm.nome, ' (', m.especialidade, ')')
                 ORDER BY pm.nome SEPARATOR '; ')            AS medicos_que_atenderam
FROM paciente pac
JOIN      pessoa   p   ON p.cpf          = pac.cpf
LEFT JOIN convenio cv  ON cv.codigo      = pac.codigo_convenio
LEFT JOIN telefone tel ON tel.cpf        = pac.cpf
LEFT JOIN alergia  a   ON a.cpf          = pac.cpf
LEFT JOIN consulta c   ON c.cpf_paciente = pac.cpf
LEFT JOIN medico   m   ON m.cpf          = c.cpf_medico
LEFT JOIN pessoa   pm  ON pm.cpf         = m.cpf
GROUP BY pac.numero_prontuario, pac.cpf, p.nome, cv.nome;

CREATE OR REPLACE VIEW vw_atendimento_completo AS
SELECT
    c.codigo                                   AS codigo_consulta,
    CASE
        WHEN EXISTS (SELECT 1 FROM retorno r
                      WHERE r.codigo_consulta_retorno = c.codigo)
        THEN 'Retorno'
        ELSE 'Primeira consulta'
    END                                        AS tipo_consulta,
    (SELECT MIN(r.codigo_consulta_origem)
       FROM retorno r
      WHERE r.codigo_consulta_retorno = c.codigo) AS retorno_da_consulta,
    pac.numero_prontuario                      AS prontuario,
    pp.nome                                    AS paciente,
    COALESCE(cv.nome, 'Particular')            AS convenio,
    pm.nome                                    AS medico,
    m.crm                                      AS crm,
    m.especialidade                            AS especialidade,
    pr.numero                                  AS numero_receita,
    (SELECT GROUP_CONCAT(med.nome ORDER BY med.nome SEPARATOR ', ')
       FROM contem ct
       JOIN medicamento med ON med.codigo = ct.codigo_medicamento
      WHERE ct.codigo_consulta = c.codigo)     AS medicamentos_prescritos,
    (SELECT GROUP_CONCAT(e.nome ORDER BY e.nome SEPARATOR ', ')
       FROM solicita s
       JOIN exame e ON e.codigo = s.codigo_exame
      WHERE s.codigo_consulta = c.codigo)      AS exames_solicitados
FROM consulta c
JOIN      paciente   pac ON pac.cpf           = c.cpf_paciente
JOIN      pessoa     pp  ON pp.cpf            = pac.cpf
LEFT JOIN convenio   cv  ON cv.codigo         = pac.codigo_convenio
JOIN      medico     m   ON m.cpf             = c.cpf_medico
JOIN      pessoa     pm  ON pm.cpf            = m.cpf
LEFT JOIN prescricao pr  ON pr.codigo_consulta = c.codigo;



USE prontuario_medico;

SELECT
    c.codigo                AS codigo_consulta,
    p_pac.nome              AS paciente,
    pac.numero_prontuario   AS prontuario,
    p_med.nome              AS medico,
    m.especialidade         AS especialidade,
    m.crm                   AS crm
FROM consulta c
JOIN paciente pac   ON pac.cpf  = c.cpf_paciente
JOIN pessoa   p_pac ON p_pac.cpf = pac.cpf
JOIN medico   m     ON m.cpf    = c.cpf_medico
JOIN pessoa   p_med ON p_med.cpf = m.cpf
ORDER BY c.codigo;

SELECT
    m.especialidade      AS especialidade,
    COUNT(*)             AS total_consultas
FROM consulta c
JOIN medico m ON m.cpf = c.cpf_medico
GROUP BY m.especialidade
ORDER BY total_consultas DESC;

SELECT
    med.nome              AS medicamento,
    COUNT(*)              AS vezes_prescrito
FROM contem ct
JOIN medicamento med ON med.codigo = ct.codigo_medicamento
GROUP BY med.nome
ORDER BY vezes_prescrito DESC, medicamento ASC
LIMIT 10;

SELECT
    p.nome                  AS paciente,
    pac.numero_prontuario   AS prontuario,
    COUNT(*)                AS quantidade_alergias
FROM alergia a
JOIN paciente pac ON pac.cpf = a.cpf
JOIN pessoa   p   ON p.cpf   = pac.cpf
GROUP BY p.nome, pac.numero_prontuario
HAVING COUNT(*) > 1
ORDER BY quantidade_alergias DESC, paciente;

SELECT
    COALESCE(cv.nome, 'Particular (sem convênio)') AS convenio,
    COUNT(*)                                        AS total_pacientes
FROM paciente pac
LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
GROUP BY COALESCE(cv.nome, 'Particular (sem convênio)')
ORDER BY total_pacientes DESC;

SELECT
    p.nome                   AS medico,
    m.especialidade          AS especialidade,
    COUNT(c.codigo)          AS total_consultas,
    ROUND((SELECT COUNT(*) FROM consulta) / (SELECT COUNT(*) FROM medico), 2) AS media_por_medico
FROM medico m
JOIN pessoa   p ON p.cpf        = m.cpf
JOIN consulta c ON c.cpf_medico = m.cpf
GROUP BY m.cpf, p.nome, m.especialidade
HAVING COUNT(c.codigo) > (SELECT COUNT(*) FROM consulta) / (SELECT COUNT(*) FROM medico)
ORDER BY total_consultas DESC, medico;

SELECT
    p.nome                           AS paciente,
    pac.numero_prontuario            AS prontuario,
    COALESCE(cv.nome, 'Particular')  AS convenio
FROM paciente pac
JOIN pessoa p         ON p.cpf     = pac.cpf
LEFT JOIN convenio cv ON cv.codigo = pac.codigo_convenio
WHERE NOT EXISTS (
    SELECT 1
    FROM consulta c
    WHERE c.cpf_paciente = pac.cpf
)
ORDER BY p.nome;

SELECT
    r.codigo_consulta_origem    AS consulta_origem,
    r.codigo_consulta_retorno   AS consulta_retorno,
    pp.nome                     AS paciente,
    pm.nome                     AS medico_retorno,
    (SELECT COUNT(*)
       FROM contem ct
      WHERE ct.codigo_consulta = r.codigo_consulta_retorno) AS qtd_medicamentos,
    (SELECT GROUP_CONCAT(e.nome ORDER BY e.nome SEPARATOR ', ')
       FROM solicita s
       JOIN exame e ON e.codigo = s.codigo_exame
      WHERE s.codigo_consulta = r.codigo_consulta_retorno)  AS exames_retorno
FROM retorno r
JOIN consulta co ON co.codigo = r.codigo_consulta_origem
JOIN consulta cr ON cr.codigo = r.codigo_consulta_retorno
JOIN pessoa   pp ON pp.cpf    = co.cpf_paciente
JOIN pessoa   pm ON pm.cpf    = cr.cpf_medico
ORDER BY r.codigo_consulta_origem;

USE prontuario_medico;

SELECT
    cv.codigo  AS codigo_convenio,
    cv.nome    AS convenio_sem_pacientes
FROM convenio cv
LEFT JOIN paciente pac
       ON pac.codigo_convenio = cv.codigo
WHERE pac.cpf IS NULL
ORDER BY cv.nome;

WITH exames_primeira_consulta AS (
    SELECT s.codigo_exame,
           COUNT(*) AS qtd_pedidos
    FROM solicita s
    WHERE NOT EXISTS (SELECT 1
                        FROM retorno r
                       WHERE r.codigo_consulta_retorno = s.codigo_consulta)
    GROUP BY s.codigo_exame
),
exames_retorno AS (
    SELECT s.codigo_exame,
           COUNT(*) AS qtd_pedidos
    FROM solicita s
    WHERE EXISTS (SELECT 1
                    FROM retorno r
                   WHERE r.codigo_consulta_retorno = s.codigo_consulta)
    GROUP BY s.codigo_exame
)
SELECT
    e.nome                                    AS exame,
    resultado.pedidos_primeira_consulta,
    resultado.pedidos_retorno,
    CASE
        WHEN resultado.pedidos_retorno = 0           THEN 'Só investigação (1ª consulta)'
        WHEN resultado.pedidos_primeira_consulta = 0 THEN 'Só acompanhamento (retorno)'
        ELSE 'Investigação e acompanhamento'
    END                                       AS uso_clinico
FROM (
        SELECT COALESCE(pc.codigo_exame, rt.codigo_exame) AS codigo_exame,
               COALESCE(pc.qtd_pedidos, 0)                AS pedidos_primeira_consulta,
               COALESCE(rt.qtd_pedidos, 0)                AS pedidos_retorno
        FROM exames_primeira_consulta pc
        LEFT JOIN exames_retorno rt
               ON rt.codigo_exame = pc.codigo_exame

        UNION ALL

        SELECT rt.codigo_exame,
               0,
               rt.qtd_pedidos
        FROM exames_primeira_consulta pc
        RIGHT JOIN exames_retorno rt
                ON rt.codigo_exame = pc.codigo_exame
        WHERE pc.codigo_exame IS NULL
     ) AS resultado
JOIN exame e
  ON e.codigo = resultado.codigo_exame
ORDER BY uso_clinico, e.nome;

SELECT
    p.nome                   AS paciente,
    pac.numero_prontuario    AS prontuario,
    (SELECT GROUP_CONCAT(a.alergia ORDER BY a.alergia SEPARATOR ', ')
       FROM alergia a
      WHERE a.cpf = pac.cpf
        AND a.alergia IN ('Dipirona', 'Ibuprofeno', 'Anti-inflamatórios')
    )                        AS alergias_de_risco,
    (SELECT GROUP_CONCAT(DISTINCT CONCAT(med.nome, ' — consulta ', c.codigo,
                                         ', Dr(a). ', pm.nome)
                         ORDER BY c.codigo SEPARATOR ' | ')
       FROM consulta c
       JOIN contem      ct  ON ct.codigo_consulta = c.codigo
       JOIN medicamento med ON med.codigo         = ct.codigo_medicamento
       JOIN pessoa      pm  ON pm.cpf             = c.cpf_medico
      WHERE c.cpf_paciente = pac.cpf
        AND med.nome REGEXP '^(Dipirona|Ibuprofeno|Diclofenaco|Nimesulida)'
    )                        AS prescricoes_para_revisar
FROM paciente pac
JOIN pessoa p
  ON p.cpf = pac.cpf
WHERE pac.cpf IN (SELECT a.cpf
                    FROM alergia a
                   WHERE a.alergia IN ('Dipirona', 'Ibuprofeno', 'Anti-inflamatórios'))
  AND EXISTS (SELECT 1
                FROM consulta c
                JOIN contem      ct  ON ct.codigo_consulta = c.codigo
                JOIN medicamento med ON med.codigo         = ct.codigo_medicamento
               WHERE c.cpf_paciente = pac.cpf
                 AND med.nome REGEXP '^(Dipirona|Ibuprofeno|Diclofenaco|Nimesulida)')
ORDER BY p.nome;

SELECT
    p.nome                                   AS paciente,
    pac.numero_prontuario                    AS prontuario,
    por_paciente.qtd_medicamentos            AS medicamentos_distintos,
    (SELECT ROUND(AVG(t.qtd), 2)
       FROM (SELECT COUNT(DISTINCT ct2.codigo_medicamento) AS qtd
               FROM consulta c2
               JOIN contem ct2 ON ct2.codigo_consulta = c2.codigo
              GROUP BY c2.cpf_paciente) AS t
    )                                        AS media_da_clinica,
    CASE
        WHEN por_paciente.qtd_medicamentos >= 5 THEN 'Polifarmácia — revisar medicação'
        ELSE 'Acima da média'
    END                                      AS situacao
FROM (
        SELECT c.cpf_paciente,
               COUNT(DISTINCT ct.codigo_medicamento) AS qtd_medicamentos
        FROM consulta c
        JOIN contem ct ON ct.codigo_consulta = c.codigo
        GROUP BY c.cpf_paciente
     ) AS por_paciente
JOIN paciente pac ON pac.cpf = por_paciente.cpf_paciente
JOIN pessoa   p   ON p.cpf   = pac.cpf
WHERE por_paciente.qtd_medicamentos >
      (SELECT AVG(t.qtd)
         FROM (SELECT COUNT(DISTINCT ct2.codigo_medicamento) AS qtd
                 FROM consulta c2
                 JOIN contem ct2 ON ct2.codigo_consulta = c2.codigo
                GROUP BY c2.cpf_paciente) AS t)
ORDER BY por_paciente.qtd_medicamentos DESC, p.nome;
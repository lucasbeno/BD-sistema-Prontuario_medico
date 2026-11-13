-- =====================================================================
-- ETAPA 06 — AJUSTES PARA A INTERFACE FINAL E O DASHBOARD
-- Sistema de Prontuário Médico (Clínica VidaPlena) — MySQL 8.0.13+
-- Executar DEPOIS dos scripts das Etapas 01 a 05:
--   01_tabelas -> 02_insercao -> 04_indices -> 04_visoes ->
--   05_funcoes -> 05_procedimentos -> 05_triggers -> 06_dashboard
-- (ou rode apenas sql/instalar_tudo.sql, que junta todos na ordem certa)
-- =====================================================================
USE prontuario_medico;


-- =====================================================================
-- 1) DATA DA CONSULTA
--
-- Justificativa: o dashboard da Etapa 06 pede tendências temporais e
-- filtro por período ("consultas por mês", "selecionar períodos"). Até a
-- Etapa 05 a consulta não guardava QUANDO aconteceu, então não havia como
-- fazer nenhuma análise no tempo. A coluna nova resolve isso:
--   - NOT NULL: toda consulta acontece em uma data.
--   - DEFAULT (CURRENT_DATE): quem não informar a data (por exemplo, o
--     procedimento sp_agendar_pacientes_sem_consulta da Etapa 05, que faz
--     INSERT sem essa coluna) continua funcionando e grava a data de hoje.
--     (DEFAULT com expressão exige MySQL 8.0.13 ou superior.)
-- =====================================================================
ALTER TABLE consulta
    ADD COLUMN data_consulta DATE NOT NULL DEFAULT (CURRENT_DATE);


-- Datas das 64 consultas já cadastradas (nov/2025 a out/2026).
-- Regras respeitadas:
--   - só dias úteis (a clínica não abre no fim de semana);
--   - todo retorno acontece DEPOIS da consulta de origem
--     (consultas 31–60 são retornos das 1–30; 61–64 são retornos das 31–34);
--   - volume crescente ao longo do ano (clínica em expansão), o que gera
--     uma tendência visível no gráfico de linha do dashboard.
CREATE TEMPORARY TABLE tmp_datas_consulta (
    codigo         INT  NOT NULL PRIMARY KEY,
    data_consulta  DATE NOT NULL
);

INSERT INTO tmp_datas_consulta (codigo, data_consulta) VALUES
    ( 1, '2025-11-17'),
    ( 2, '2026-02-02'),
    ( 3, '2026-02-27'),
    ( 4, '2026-03-03'),
    ( 5, '2026-03-06'),
    ( 6, '2026-03-20'),
    ( 7, '2026-03-20'),
    ( 8, '2026-04-06'),
    ( 9, '2026-05-12'),
    (10, '2026-05-20'),
    (11, '2026-05-20'),
    (12, '2026-05-20'),
    (13, '2026-05-28'),
    (14, '2026-05-28'),
    (15, '2026-06-05'),
    (16, '2026-06-08'),
    (17, '2026-06-08'),
    (18, '2026-06-18'),
    (19, '2026-07-01'),
    (20, '2026-07-09'),
    (21, '2026-07-10'),
    (22, '2026-08-03'),
    (23, '2026-08-21'),
    (24, '2026-08-21'),
    (25, '2026-09-01'),
    (26, '2026-09-03'),
    (27, '2026-09-08'),
    (28, '2026-09-16'),
    (29, '2026-09-24'),
    (30, '2026-09-24'),
    (31, '2025-12-09'),
    (32, '2026-03-02'),
    (33, '2026-03-16'),
    (34, '2026-04-10'),
    (35, '2026-03-30'),
    (36, '2026-04-10'),
    (37, '2026-04-22'),
    (38, '2026-05-15'),
    (39, '2026-06-04'),
    (40, '2026-07-01'),
    (41, '2026-07-02'),
    (42, '2026-06-30'),
    (43, '2026-07-09'),
    (44, '2026-06-23'),
    (45, '2026-06-22'),
    (46, '2026-07-14'),
    (47, '2026-07-16'),
    (48, '2026-07-09'),
    (49, '2026-08-12'),
    (50, '2026-07-27'),
    (51, '2026-08-19'),
    (52, '2026-09-01'),
    (53, '2026-09-23'),
    (54, '2026-09-25'),
    (55, '2026-10-06'),
    (56, '2026-10-14'),
    (57, '2026-10-12'),
    (58, '2026-10-09'),
    (59, '2026-10-22'),
    (60, '2026-10-21'),
    (61, '2026-01-09'),
    (62, '2026-04-01'),
    (63, '2026-04-14'),
    (64, '2026-05-19');

UPDATE consulta c
JOIN tmp_datas_consulta t ON t.codigo = c.codigo
SET c.data_consulta = t.data_consulta;

DROP TEMPORARY TABLE tmp_datas_consulta;


-- Índice para os filtros por período do dashboard
-- (WHERE data_consulta BETWEEN ? AND ?, GROUP BY mês).
CREATE INDEX idx_consulta_data ON consulta (data_consulta);


-- =====================================================================
-- 2) VISÃO vw_atendimento_completo (Etapa 04) — passa a mostrar a data
--
-- Mesma visão da Etapa 04 (mesmas colunas, mesmos JOINs e subconsultas),
-- só com a coluna data_consulta acrescentada logo depois do código, para
-- que a interface consiga filtrar os atendimentos por período.
-- =====================================================================
CREATE OR REPLACE VIEW vw_atendimento_completo AS
SELECT
    c.codigo                                   AS codigo_consulta,
    c.data_consulta                            AS data_consulta,
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


-- ---------------------------------------------------------------------
-- Conferências
-- ---------------------------------------------------------------------
-- Consultas por mês (base do gráfico de linha):
--   SELECT DATE_FORMAT(data_consulta, '%Y-%m') AS mes, COUNT(*) AS consultas
--     FROM consulta GROUP BY mes ORDER BY mes;
-- Nenhum retorno pode ser anterior à consulta de origem (deve voltar 0 linhas):
--   SELECT r.* FROM retorno r
--     JOIN consulta co ON co.codigo = r.codigo_consulta_origem
--     JOIN consulta cr ON cr.codigo = r.codigo_consulta_retorno
--    WHERE cr.data_consulta < co.data_consulta;

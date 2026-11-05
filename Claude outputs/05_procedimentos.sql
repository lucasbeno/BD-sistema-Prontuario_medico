-- =====================================================================
-- ETAPA 05 — PROCEDIMENTOS ARMAZENADOS
-- Sistema de Prontuário Médico (Clínica VidaPlena) — MySQL 8+
-- Executar DEPOIS de 05_funcoes.sql.
-- =====================================================================
USE prontuario_medico;

DROP PROCEDURE IF EXISTS sp_atualizar_convenio_paciente;
DROP PROCEDURE IF EXISTS sp_agendar_pacientes_sem_consulta;

DELIMITER $$


-- =====================================================================
-- PROCEDIMENTO 1 (ATUALIZAÇÃO) — sp_atualizar_convenio_paciente
--   IN p_cpf              CPF do paciente
--   IN p_codigo_convenio  novo convênio (NULL = passa a ser particular)
--
-- Justificativa semântica:
-- O paciente troca de plano de saúde (ou deixa de ter plano) e a recepção
-- precisa atualizar o cadastro. Em vez de cada tela fazer um UPDATE solto,
-- o procedimento centraliza a regra: só altera se o paciente existir e se
-- o convênio informado existir (evita erro de chave estrangeira com
-- mensagem técnica), aceita NULL para "particular" e devolve o cadastro já
-- atualizado para conferência. Como a alteração é um UPDATE em paciente,
-- ela dispara o trigger trg_paciente_log_convenio, que registra a troca
-- na tabela de log (quem, quando, de qual convênio para qual).
-- =====================================================================
CREATE PROCEDURE sp_atualizar_convenio_paciente(IN p_cpf CHAR(11),
                                                IN p_codigo_convenio INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM paciente WHERE cpf = p_cpf) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Paciente não encontrado';
    END IF;

    IF p_codigo_convenio IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM convenio WHERE codigo = p_codigo_convenio) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Convênio não encontrado';
    END IF;

    UPDATE paciente
       SET codigo_convenio = p_codigo_convenio
     WHERE cpf = p_cpf;

    SELECT pac.numero_prontuario              AS prontuario,
           p.nome                             AS paciente,
           COALESCE(cv.nome, 'Particular')    AS convenio_atual
      FROM paciente pac
      JOIN pessoa p            ON p.cpf     = pac.cpf
      LEFT JOIN convenio cv    ON cv.codigo = pac.codigo_convenio
     WHERE pac.cpf = p_cpf;
END$$


-- =====================================================================
-- PROCEDIMENTO 2 (CURSOR) — sp_agendar_pacientes_sem_consulta
--   OUT p_total_agendadas  quantas consultas foram criadas
--
-- Justificativa semântica:
-- Pacientes cadastrados que nunca foram atendidos (a Consulta 7 da Etapa 03
-- os lista) precisam de uma primeira consulta. A clínica quer distribuí-los
-- de forma equilibrada: cada paciente vai para o médico que, NAQUELE
-- MOMENTO, tem menos consultas.
--
-- Por que precisa de CURSOR (e não de um UPDATE/INSERT ... SELECT):
--   1. A escolha do médico de um paciente DEPENDE do resultado das escolhas
--      anteriores: ao encaminhar o 1º paciente, aquele médico passa a ter
--      mais uma consulta e pode deixar de ser o menos carregado para o 2º.
--      Um único comando SQL enxerga o estado de antes de começar e mandaria
--      todos os pacientes para o mesmo médico. É preciso processar uma linha
--      por vez, recalculando a carga a cada passo.
--   2. O resultado são NOVAS linhas na tabela consulta (um UPDATE só
--      modifica linhas que já existem).
--
-- Detalhe técnico: a fila de pacientes é copiada para uma tabela temporária
-- antes do laço porque o laço insere em consulta, tabela que a própria
-- consulta da fila lê; percorrer o cursor sobre uma cópia evita
-- comportamento indefinido do MySQL.
-- =====================================================================
CREATE PROCEDURE sp_agendar_pacientes_sem_consulta(OUT p_total_agendadas INT)
BEGIN
    DECLARE v_fim             INT DEFAULT 0;
    DECLARE v_cpf_paciente    CHAR(11);
    DECLARE v_cpf_medico      CHAR(11);

    DECLARE cur_fila CURSOR FOR
        SELECT cpf
          FROM tmp_fila_sem_consulta
         ORDER BY numero_prontuario;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fim = 1;

    SET p_total_agendadas = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_fila_sem_consulta;
    CREATE TEMPORARY TABLE tmp_fila_sem_consulta AS
        SELECT pac.cpf, pac.numero_prontuario
          FROM paciente pac
         WHERE NOT EXISTS (SELECT 1
                             FROM consulta c
                            WHERE c.cpf_paciente = pac.cpf);

    OPEN cur_fila;

    laco: LOOP
        FETCH cur_fila INTO v_cpf_paciente;
        IF v_fim = 1 THEN
            LEAVE laco;
        END IF;

        -- médico com menos consultas agora (empate: menor CPF)
        SET v_cpf_medico = NULL;
        SELECT m.cpf
          INTO v_cpf_medico
          FROM medico m
          LEFT JOIN consulta c ON c.cpf_medico = m.cpf
         GROUP BY m.cpf
         ORDER BY COUNT(c.codigo) ASC, m.cpf ASC
         LIMIT 1;

        -- o SELECT ... INTO acima pode ter disparado o NOT FOUND; restaura
        -- o controle do laço (só termina quando o FETCH esgotar o cursor)
        SET v_fim = 0;

        IF v_cpf_medico IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Não há médicos cadastrados para receber pacientes';
        END IF;

        INSERT INTO consulta (cpf_paciente, cpf_medico)
        VALUES (v_cpf_paciente, v_cpf_medico);

        SET p_total_agendadas = p_total_agendadas + 1;
    END LOOP laco;

    CLOSE cur_fila;
    DROP TEMPORARY TABLE IF EXISTS tmp_fila_sem_consulta;
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Exemplos de uso
-- ---------------------------------------------------------------------
-- Procedimento 1 — trocar o convênio (paciente 10000000005 é particular):
--   CALL sp_atualizar_convenio_paciente('10000000005', 2);      -- vai para Hapvida
--   CALL sp_atualizar_convenio_paciente('10000000005', NULL);   -- volta a ser particular
--   CALL sp_atualizar_convenio_paciente('10000000005', 999);    -- erro: Convênio não encontrado
--   SELECT * FROM log_auditoria ORDER BY codigo DESC;           -- as trocas ficaram registradas
--
-- Procedimento 2 — dentro de uma transação, para poder desfazer a demonstração
-- (os pacientes 10000000031 e 10000000032 não têm consulta):
--   START TRANSACTION;
--   CALL sp_agendar_pacientes_sem_consulta(@criadas);
--   SELECT @criadas AS consultas_criadas;
--   SELECT c.codigo, pp.nome AS paciente, pm.nome AS medico
--     FROM consulta c
--     JOIN pessoa pp ON pp.cpf = c.cpf_paciente
--     JOIN pessoa pm ON pm.cpf = c.cpf_medico
--    WHERE c.cpf_paciente IN ('10000000031', '10000000032');
--   ROLLBACK;     -- (ou COMMIT para manter os agendamentos)

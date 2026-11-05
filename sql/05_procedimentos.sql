USE prontuario_medico;

DROP PROCEDURE IF EXISTS sp_atualizar_convenio_paciente;
DROP PROCEDURE IF EXISTS sp_agendar_pacientes_sem_consulta;

DELIMITER $$

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

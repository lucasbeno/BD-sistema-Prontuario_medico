USE prontuario_medico;



CREATE TABLE IF NOT EXISTS log_auditoria (
    codigo     BIGINT       NOT NULL AUTO_INCREMENT,
    tabela     VARCHAR(40)  NOT NULL,
    operacao   VARCHAR(10)  NOT NULL,
    chave      VARCHAR(40)  NOT NULL,
    detalhe    VARCHAR(255) NOT NULL,
    usuario    VARCHAR(100) NOT NULL,
    data_hora  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_log_auditoria PRIMARY KEY (codigo)
);

DROP TRIGGER IF EXISTS trg_contem_bloqueia_alergia;
DROP TRIGGER IF EXISTS trg_paciente_log_convenio;

DELIMITER $$



CREATE TRIGGER trg_contem_bloqueia_alergia
BEFORE INSERT ON contem
FOR EACH ROW
BEGIN
    DECLARE v_cpf_paciente CHAR(11);

    SELECT cpf_paciente
      INTO v_cpf_paciente
      FROM consulta
     WHERE codigo = NEW.codigo_consulta;

    IF fn_paciente_alergico_a_medicamento(v_cpf_paciente, NEW.codigo_medicamento) = 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Prescrição bloqueada: o paciente tem alergia registrada a este medicamento (ou à sua classe)';
    END IF;
END$$


CREATE TRIGGER trg_paciente_log_convenio
AFTER UPDATE ON paciente
FOR EACH ROW
BEGIN
    DECLARE v_antes  VARCHAR(80);
    DECLARE v_depois VARCHAR(80);

    IF NOT (OLD.codigo_convenio <=> NEW.codigo_convenio) THEN
        SET v_antes  = COALESCE((SELECT nome FROM convenio WHERE codigo = OLD.codigo_convenio),
                                'Particular');
        SET v_depois = COALESCE((SELECT nome FROM convenio WHERE codigo = NEW.codigo_convenio),
                                'Particular');

        INSERT INTO log_auditoria (tabela, operacao, chave, detalhe, usuario)
        VALUES ('paciente', 'UPDATE', NEW.cpf,
                CONCAT('Convênio alterado de "', v_antes, '" para "', v_depois, '"'),
                CURRENT_USER());
    END IF;
END$$

DELIMITER ;



-- =====================================================================
-- ETAPA 05 — TRIGGERS
-- Sistema de Prontuário Médico (Clínica VidaPlena) — MySQL 8+
-- Executar DEPOIS de 05_funcoes.sql (o trigger 1 usa a função 2).
--
-- Já existiam (Etapa 03): trg_consulta_pessoas_ins/upd e
-- trg_retorno_distinta_ins/upd. Os dois abaixo são novos.
-- =====================================================================
USE prontuario_medico;


-- =====================================================================
-- TABELA DE LOG — log_auditoria
-- Guarda o histórico de alterações sensíveis do prontuário: em qual
-- tabela, que operação, qual registro, o que mudou, quem e quando.
-- =====================================================================
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


-- =====================================================================
-- TRIGGER 1 — trg_contem_bloqueia_alergia
-- Evento: BEFORE INSERT em contem (item de uma receita)
--
-- Justificativa semântica:
-- "contem" liga a receita ao medicamento prescrito. Antes de gravar cada
-- item, o trigger descobre quem é o paciente da consulta e usa a função
-- fn_paciente_alergico_a_medicamento: se o paciente tem alergia ao
-- medicamento (ou à classe dele), a gravação é RECUSADA com uma mensagem
-- clara. A regra fica no banco, então vale para qualquer tela, script ou
-- aplicação que tente prescrever, e não só para a interface atual.
-- (BEFORE, e não AFTER: o item perigoso não chega a ser gravado.)
-- =====================================================================
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


-- =====================================================================
-- TRIGGER 2 (LOG) — trg_paciente_log_convenio
-- Evento: AFTER UPDATE em paciente
--
-- Justificativa semântica:
-- O convênio define quem paga o atendimento e quais coberturas valem.
-- Quando ele muda, a clínica precisa saber quem alterou, quando e de qual
-- plano para qual (auditoria do cadastro e conferência de cobranças). O
-- trigger grava uma linha em log_auditoria SOMENTE quando o convênio
-- realmente mudou (comparação com <=>, que trata NULL = particular), de
-- modo que atualizações de outras colunas não poluem o log.
-- (AFTER: o registro só é feito depois que a alteração foi aceita.)
-- =====================================================================
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


-- ---------------------------------------------------------------------
-- Exemplos de uso
-- ---------------------------------------------------------------------
-- Trigger 1 — paciente 10000000001 é alérgico a Dipirona; a consulta 61
-- é dele e já tem receita. Tentar incluir Dipirona (medicamento 2) falha:
--   INSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES (61, 2);
--   -- ERRO 1644: Prescrição bloqueada: o paciente tem alergia registrada ...
-- Um medicamento sem conflito entra normalmente (dentro de transação, para desfazer):
--   START TRANSACTION;
--   INSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES (61, 3);  -- Paracetamol
--   ROLLBACK;
--
-- Trigger 2 — qualquer UPDATE que mude o convênio gera log:
--   UPDATE paciente SET codigo_convenio = 2 WHERE cpf = '10000000005';
--   UPDATE paciente SET codigo_convenio = NULL WHERE cpf = '10000000005';
--   SELECT * FROM log_auditoria ORDER BY codigo DESC;

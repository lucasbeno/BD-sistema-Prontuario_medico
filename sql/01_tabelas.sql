DROP DATABASE IF EXISTS prontuario_medico;
CREATE DATABASE prontuario_medico
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_0900_ai_ci;
USE prontuario_medico;

CREATE TABLE pessoa (
    cpf          CHAR(11)     NOT NULL,
    nome         VARCHAR(100) NOT NULL,
    cep          CHAR(8)      NOT NULL,
    numero_apto  VARCHAR(10)  DEFAULT 'S/N',
    CONSTRAINT pk_pessoa       PRIMARY KEY (cpf),
    CONSTRAINT ck_pessoa_cpf   CHECK (cpf REGEXP '^[0-9]{11}$'),
    CONSTRAINT ck_pessoa_cep   CHECK (cep REGEXP '^[0-9]{8}$'),
    CONSTRAINT ck_pessoa_nome  CHECK (CHAR_LENGTH(TRIM(nome)) >= 3)
);

CREATE TABLE telefone (
    cpf       CHAR(11)    NOT NULL,
    telefone  VARCHAR(15) NOT NULL,
    CONSTRAINT pk_telefone          PRIMARY KEY (cpf, telefone),
    CONSTRAINT fk_telefone_pessoa   FOREIGN KEY (cpf) REFERENCES pessoa (cpf)
                                    ON UPDATE CASCADE
                                    ON DELETE CASCADE,
    CONSTRAINT ck_telefone_formato  CHECK (telefone REGEXP '^[0-9]{10,11}$')
);

CREATE TABLE convenio (
    codigo  INT         NOT NULL AUTO_INCREMENT,
    nome    VARCHAR(80) NOT NULL,
    CONSTRAINT pk_convenio      PRIMARY KEY (codigo),
    CONSTRAINT un_convenio_nome UNIQUE (nome),
    CONSTRAINT ck_convenio_nome CHECK (CHAR_LENGTH(TRIM(nome)) >= 2)
) AUTO_INCREMENT = 1;

CREATE TABLE paciente (
    cpf                CHAR(11) NOT NULL,
    numero_prontuario  INT      NOT NULL AUTO_INCREMENT,
    codigo_convenio    INT      DEFAULT NULL,
    CONSTRAINT pk_paciente             PRIMARY KEY (cpf),
    CONSTRAINT un_paciente_prontuario  UNIQUE (numero_prontuario),
    CONSTRAINT fk_paciente_pessoa      FOREIGN KEY (cpf) REFERENCES pessoa (cpf)
                                       ON UPDATE CASCADE
                                       ON DELETE CASCADE,
    CONSTRAINT fk_paciente_convenio    FOREIGN KEY (codigo_convenio) REFERENCES convenio (codigo)
                                       ON UPDATE CASCADE
                                       ON DELETE SET NULL
) AUTO_INCREMENT = 1001;

CREATE TABLE alergia (
    cpf      CHAR(11)    NOT NULL,
    alergia  VARCHAR(60) NOT NULL,
    CONSTRAINT pk_alergia           PRIMARY KEY (cpf, alergia),
    CONSTRAINT fk_alergia_paciente  FOREIGN KEY (cpf) REFERENCES paciente (cpf)
                                    ON UPDATE CASCADE
                                    ON DELETE CASCADE,
    CONSTRAINT ck_alergia_descricao CHECK (CHAR_LENGTH(TRIM(alergia)) >= 3)
);

CREATE TABLE medico (
    cpf            CHAR(11)    NOT NULL,
    crm            VARCHAR(15) NOT NULL,
    especialidade  VARCHAR(60) NOT NULL DEFAULT 'Clínica Geral',
    CONSTRAINT pk_medico               PRIMARY KEY (cpf),
    CONSTRAINT fk_medico_pessoa        FOREIGN KEY (cpf) REFERENCES pessoa (cpf)
                                       ON UPDATE CASCADE
                                       ON DELETE CASCADE,
    CONSTRAINT un_medico_crm           UNIQUE (crm),
    CONSTRAINT ck_medico_crm           CHECK (crm REGEXP '^[0-9]{4,6}/[A-Z]{2}$'),
    CONSTRAINT ck_medico_especialidade CHECK (CHAR_LENGTH(TRIM(especialidade)) >= 3)
);

CREATE TABLE consulta (
    codigo        INT      NOT NULL AUTO_INCREMENT,
    cpf_paciente  CHAR(11) NOT NULL,
    cpf_medico    CHAR(11) NOT NULL,
    CONSTRAINT pk_consulta            PRIMARY KEY (codigo),
    CONSTRAINT fk_consulta_paciente   FOREIGN KEY (cpf_paciente) REFERENCES paciente (cpf)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT,
    CONSTRAINT fk_consulta_medico     FOREIGN KEY (cpf_medico) REFERENCES medico (cpf)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT
) AUTO_INCREMENT = 1;

CREATE TABLE retorno (
    codigo_consulta_origem   INT NOT NULL,
    codigo_consulta_retorno  INT NOT NULL,
    CONSTRAINT pk_retorno          PRIMARY KEY (codigo_consulta_origem, codigo_consulta_retorno),
    CONSTRAINT fk_retorno_origem   FOREIGN KEY (codigo_consulta_origem) REFERENCES consulta (codigo)
                                   ON UPDATE CASCADE
                                   ON DELETE CASCADE,
    CONSTRAINT fk_retorno_retorno  FOREIGN KEY (codigo_consulta_retorno) REFERENCES consulta (codigo)
                                   ON UPDATE CASCADE
                                   ON DELETE CASCADE
);

CREATE TABLE prescricao (
    codigo_consulta  INT          NOT NULL,
    numero           INT          NOT NULL AUTO_INCREMENT,
    nome             VARCHAR(100) DEFAULT 'Receita padrão',
    CONSTRAINT pk_prescricao           PRIMARY KEY (codigo_consulta),
    CONSTRAINT un_prescricao_numero    UNIQUE (numero),
    CONSTRAINT fk_prescricao_consulta  FOREIGN KEY (codigo_consulta) REFERENCES consulta (codigo)
                                       ON UPDATE CASCADE
                                       ON DELETE CASCADE
) AUTO_INCREMENT = 5001;

CREATE TABLE medicamento (
    codigo  INT          NOT NULL AUTO_INCREMENT,
    nome    VARCHAR(100) NOT NULL,
    CONSTRAINT pk_medicamento      PRIMARY KEY (codigo),
    CONSTRAINT un_medicamento_nome UNIQUE (nome),
    CONSTRAINT ck_medicamento_nome CHECK (CHAR_LENGTH(TRIM(nome)) >= 3)
) AUTO_INCREMENT = 1;

CREATE TABLE contem (
    codigo_consulta     INT NOT NULL,
    codigo_medicamento  INT NOT NULL,
    CONSTRAINT pk_contem              PRIMARY KEY (codigo_consulta, codigo_medicamento),
    CONSTRAINT fk_contem_prescricao   FOREIGN KEY (codigo_consulta) REFERENCES prescricao (codigo_consulta)
                                      ON UPDATE CASCADE
                                      ON DELETE CASCADE,
    CONSTRAINT fk_contem_medicamento  FOREIGN KEY (codigo_medicamento) REFERENCES medicamento (codigo)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT
);

CREATE TABLE exame (
    codigo  INT          NOT NULL AUTO_INCREMENT,
    nome    VARCHAR(100) NOT NULL,
    CONSTRAINT pk_exame      PRIMARY KEY (codigo),
    CONSTRAINT un_exame_nome UNIQUE (nome),
    CONSTRAINT ck_exame_nome CHECK (CHAR_LENGTH(TRIM(nome)) >= 3)
) AUTO_INCREMENT = 1;

CREATE TABLE solicita (
    codigo_consulta  INT NOT NULL,
    codigo_exame     INT NOT NULL,
    CONSTRAINT pk_solicita           PRIMARY KEY (codigo_consulta, codigo_exame),
    CONSTRAINT fk_solicita_consulta  FOREIGN KEY (codigo_consulta) REFERENCES consulta (codigo)
                                     ON UPDATE CASCADE
                                     ON DELETE CASCADE,
    CONSTRAINT fk_solicita_exame     FOREIGN KEY (codigo_exame) REFERENCES exame (codigo)
                                     ON UPDATE CASCADE
                                     ON DELETE RESTRICT
);

DELIMITER $$

CREATE TRIGGER trg_consulta_pessoas_ins BEFORE INSERT ON consulta
FOR EACH ROW
BEGIN
    IF NEW.cpf_paciente = NEW.cpf_medico THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'O paciente e o médico da consulta devem ser pessoas diferentes';
    END IF;
END$$

CREATE TRIGGER trg_consulta_pessoas_upd BEFORE UPDATE ON consulta
FOR EACH ROW
BEGIN
    IF NEW.cpf_paciente = NEW.cpf_medico THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'O paciente e o médico da consulta devem ser pessoas diferentes';
    END IF;
END$$

CREATE TRIGGER trg_retorno_distinta_ins BEFORE INSERT ON retorno
FOR EACH ROW
BEGIN
    IF NEW.codigo_consulta_origem = NEW.codigo_consulta_retorno THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A consulta de retorno deve ser diferente da consulta de origem';
    END IF;
END$$

CREATE TRIGGER trg_retorno_distinta_upd BEFORE UPDATE ON retorno
FOR EACH ROW
BEGIN
    IF NEW.codigo_consulta_origem = NEW.codigo_consulta_retorno THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A consulta de retorno deve ser diferente da consulta de origem';
    END IF;
END$$

DELIMITER ;

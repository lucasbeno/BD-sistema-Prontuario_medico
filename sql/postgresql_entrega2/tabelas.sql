DROP TABLE IF EXISTS solicita CASCADE;
DROP TABLE IF EXISTS exame CASCADE;
DROP TABLE IF EXISTS contem CASCADE;
DROP TABLE IF EXISTS medicamento CASCADE;
DROP TABLE IF EXISTS prescricao CASCADE;
DROP TABLE IF EXISTS retorno CASCADE;
DROP TABLE IF EXISTS consulta CASCADE;
DROP TABLE IF EXISTS medico CASCADE;
DROP TABLE IF EXISTS alergia CASCADE;
DROP TABLE IF EXISTS paciente CASCADE;
DROP TABLE IF EXISTS convenio CASCADE;
DROP TABLE IF EXISTS telefone CASCADE;
DROP TABLE IF EXISTS pessoa CASCADE;

DROP SEQUENCE IF EXISTS seq_convenio CASCADE;
DROP SEQUENCE IF EXISTS seq_prontuario CASCADE;
DROP SEQUENCE IF EXISTS seq_consulta CASCADE;
DROP SEQUENCE IF EXISTS seq_prescricao_numero CASCADE;
DROP SEQUENCE IF EXISTS seq_medicamento CASCADE;
DROP SEQUENCE IF EXISTS seq_exame CASCADE;

CREATE SEQUENCE seq_convenio            START WITH 1    INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE seq_prontuario          START WITH 1001 INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE seq_consulta            START WITH 1    INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE seq_prescricao_numero   START WITH 5001 INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE seq_medicamento         START WITH 1    INCREMENT BY 1 MINVALUE 1;
CREATE SEQUENCE seq_exame               START WITH 1    INCREMENT BY 1 MINVALUE 1;

CREATE TABLE pessoa (
    cpf          CHAR(11)     NOT NULL,
    nome         VARCHAR(100) NOT NULL,
    cep          CHAR(8)      NOT NULL,
    numero_apto  VARCHAR(10)  DEFAULT 'S/N',
    CONSTRAINT pk_pessoa       PRIMARY KEY (cpf),
    CONSTRAINT ck_pessoa_cpf   CHECK (cpf ~ '^[0-9]{11}$'),
    CONSTRAINT ck_pessoa_cep   CHECK (cep ~ '^[0-9]{8}$'),
    CONSTRAINT ck_pessoa_nome  CHECK (char_length(btrim(nome)) >= 3)
);

CREATE TABLE telefone (
    cpf       CHAR(11)    NOT NULL,
    telefone  VARCHAR(15) NOT NULL,
    CONSTRAINT pk_telefone          PRIMARY KEY (cpf, telefone),
    CONSTRAINT fk_telefone_pessoa   FOREIGN KEY (cpf) REFERENCES pessoa (cpf)
                                    ON UPDATE CASCADE
                                    ON DELETE CASCADE,
    CONSTRAINT ck_telefone_formato  CHECK (telefone ~ '^[0-9]{10,11}$')
);

CREATE TABLE convenio (
    codigo  INTEGER     NOT NULL DEFAULT nextval('seq_convenio'),
    nome    VARCHAR(80) NOT NULL,
    CONSTRAINT pk_convenio      PRIMARY KEY (codigo),
    CONSTRAINT un_convenio_nome UNIQUE (nome),
    CONSTRAINT ck_convenio_nome CHECK (char_length(btrim(nome)) >= 2)
);

ALTER SEQUENCE seq_convenio OWNED BY convenio.codigo;

CREATE TABLE paciente (
    cpf                CHAR(11) NOT NULL,
    numero_prontuario  INTEGER  NOT NULL DEFAULT nextval('seq_prontuario'),
    codigo_convenio    INTEGER  DEFAULT NULL,
    CONSTRAINT pk_paciente             PRIMARY KEY (cpf),
    CONSTRAINT fk_paciente_pessoa      FOREIGN KEY (cpf) REFERENCES pessoa (cpf)
                                       ON UPDATE CASCADE
                                       ON DELETE CASCADE,
    CONSTRAINT fk_paciente_convenio    FOREIGN KEY (codigo_convenio) REFERENCES convenio (codigo)
                                       ON UPDATE CASCADE
                                       ON DELETE SET NULL,
    CONSTRAINT un_paciente_prontuario  UNIQUE (numero_prontuario),
    CONSTRAINT ck_paciente_prontuario  CHECK (numero_prontuario > 0)
);

ALTER SEQUENCE seq_prontuario OWNED BY paciente.numero_prontuario;

CREATE TABLE alergia (
    cpf      CHAR(11)    NOT NULL,
    alergia  VARCHAR(60) NOT NULL,
    CONSTRAINT pk_alergia           PRIMARY KEY (cpf, alergia),
    CONSTRAINT fk_alergia_paciente  FOREIGN KEY (cpf) REFERENCES paciente (cpf)
                                    ON UPDATE CASCADE
                                    ON DELETE CASCADE,
    CONSTRAINT ck_alergia_descricao CHECK (char_length(btrim(alergia)) >= 3)
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
    CONSTRAINT ck_medico_crm           CHECK (crm ~ '^[0-9]{4,6}/[A-Z]{2}$'),
    CONSTRAINT ck_medico_especialidade CHECK (char_length(btrim(especialidade)) >= 3)
);

CREATE TABLE consulta (
    codigo        INTEGER  NOT NULL DEFAULT nextval('seq_consulta'),
    cpf_paciente  CHAR(11) NOT NULL,
    cpf_medico    CHAR(11) NOT NULL,
    CONSTRAINT pk_consulta            PRIMARY KEY (codigo),
    CONSTRAINT fk_consulta_paciente   FOREIGN KEY (cpf_paciente) REFERENCES paciente (cpf)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT,
    CONSTRAINT fk_consulta_medico     FOREIGN KEY (cpf_medico) REFERENCES medico (cpf)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT,
    CONSTRAINT ck_consulta_pessoas    CHECK (cpf_paciente <> cpf_medico)
);

ALTER SEQUENCE seq_consulta OWNED BY consulta.codigo;

CREATE TABLE retorno (
    codigo_consulta_origem   INTEGER NOT NULL,
    codigo_consulta_retorno  INTEGER NOT NULL,
    CONSTRAINT pk_retorno          PRIMARY KEY (codigo_consulta_origem, codigo_consulta_retorno),
    CONSTRAINT fk_retorno_origem   FOREIGN KEY (codigo_consulta_origem) REFERENCES consulta (codigo)
                                   ON UPDATE CASCADE
                                   ON DELETE CASCADE,
    CONSTRAINT fk_retorno_retorno  FOREIGN KEY (codigo_consulta_retorno) REFERENCES consulta (codigo)
                                   ON UPDATE CASCADE
                                   ON DELETE CASCADE,
    CONSTRAINT ck_retorno_distinta CHECK (codigo_consulta_origem <> codigo_consulta_retorno)
);

CREATE TABLE prescricao (
    codigo_consulta  INTEGER      NOT NULL,
    numero           INTEGER      NOT NULL DEFAULT nextval('seq_prescricao_numero'),
    nome             VARCHAR(100) DEFAULT 'Receita padrão',
    CONSTRAINT pk_prescricao           PRIMARY KEY (codigo_consulta),
    CONSTRAINT fk_prescricao_consulta  FOREIGN KEY (codigo_consulta) REFERENCES consulta (codigo)
                                       ON UPDATE CASCADE
                                       ON DELETE CASCADE,
    CONSTRAINT un_prescricao_numero    UNIQUE (numero),
    CONSTRAINT ck_prescricao_numero    CHECK (numero > 0)
);

ALTER SEQUENCE seq_prescricao_numero OWNED BY prescricao.numero;

CREATE TABLE medicamento (
    codigo  INTEGER      NOT NULL DEFAULT nextval('seq_medicamento'),
    nome    VARCHAR(100) NOT NULL,
    CONSTRAINT pk_medicamento      PRIMARY KEY (codigo),
    CONSTRAINT un_medicamento_nome UNIQUE (nome),
    CONSTRAINT ck_medicamento_nome CHECK (char_length(btrim(nome)) >= 3)
);

ALTER SEQUENCE seq_medicamento OWNED BY medicamento.codigo;

CREATE TABLE contem (
    codigo_consulta     INTEGER NOT NULL,
    codigo_medicamento  INTEGER NOT NULL,
    CONSTRAINT pk_contem              PRIMARY KEY (codigo_consulta, codigo_medicamento),
    CONSTRAINT fk_contem_prescricao   FOREIGN KEY (codigo_consulta) REFERENCES prescricao (codigo_consulta)
                                      ON UPDATE CASCADE
                                      ON DELETE CASCADE,
    CONSTRAINT fk_contem_medicamento  FOREIGN KEY (codigo_medicamento) REFERENCES medicamento (codigo)
                                      ON UPDATE CASCADE
                                      ON DELETE RESTRICT
);

CREATE TABLE exame (
    codigo  INTEGER      NOT NULL DEFAULT nextval('seq_exame'),
    nome    VARCHAR(100) NOT NULL,
    CONSTRAINT pk_exame      PRIMARY KEY (codigo),
    CONSTRAINT un_exame_nome UNIQUE (nome),
    CONSTRAINT ck_exame_nome CHECK (char_length(btrim(nome)) >= 3)
);

ALTER SEQUENCE seq_exame OWNED BY exame.codigo;

CREATE TABLE solicita (
    codigo_consulta  INTEGER NOT NULL,
    codigo_exame     INTEGER NOT NULL,
    CONSTRAINT pk_solicita           PRIMARY KEY (codigo_consulta, codigo_exame),
    CONSTRAINT fk_solicita_consulta  FOREIGN KEY (codigo_consulta) REFERENCES consulta (codigo)
                                     ON UPDATE CASCADE
                                     ON DELETE CASCADE,
    CONSTRAINT fk_solicita_exame     FOREIGN KEY (codigo_exame) REFERENCES exame (codigo)
                                     ON UPDATE CASCADE
                                     ON DELETE RESTRICT
);

-- =====================================================================
-- INSTALAÇÃO COMPLETA DO BANCO — Sistema de Prontuário Médico (VidaPlena)
-- Gerado a partir dos scripts de cada etapa, na ordem de execução:
--   sql/01_tabelas.sql
--   sql/02_insercao.sql
--   sql/04_indices.sql
--   sql/04_visoes.sql
--   sql/05_funcoes.sql
--   sql/05_procedimentos.sql
--   sql/05_triggers.sql
--   sql/06_dashboard.sql
-- Rode este arquivo inteiro (Workbench: abrir e clicar no raio; terminal:
--   mysql -u root -p < sql/instalar_tudo.sql). Ele APAGA e recria o banco.
-- =====================================================================
SET NAMES utf8mb4;  -- garante acentos corretos mesmo se o cliente estiver em latin1


-- >>>>>>>>>>>>>>>>>>>> sql/01_tabelas.sql <<<<<<<<<<<<<<<<<<<<
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



-- >>>>>>>>>>>>>>>>>>>> sql/02_insercao.sql <<<<<<<<<<<<<<<<<<<<
USE prontuario_medico;

INSERT INTO pessoa (cpf, nome, cep, numero_apto) VALUES
    ('10000000001', 'Ana Beatriz Correia', '50050000', '101'),
    ('10000000002', 'Bruno Henrique Alves', '50030230', '502'),
    ('10000000003', 'Carla Menezes Lima', '50710465', DEFAULT),
    ('10000000004', 'Diego Ferreira Rocha', '51020100', '1203'),
    ('10000000005', 'Elaine Souza Martins', '52011010', '304'),
    ('10000000006', 'Fábio Moreira Gomes', '53230630', '78'),
    ('10000000007', 'Gabriela Nunes Teixeira', '54410100', '905'),
    ('10000000008', 'Henrique Barbosa Pinto', '55016000', DEFAULT),
    ('10000000009', 'Isabela Ramos Cavalcanti', '50670901', '212'),
    ('10000000010', 'João Pedro Monteiro', '51160000', '1501'),
    ('10000000011', 'Karina Lopes Andrade', '52060000', '33'),
    ('10000000012', 'Leonardo Vasconcelos Sá', '50751330', '807'),
    ('10000000013', 'Mariana Duarte Freitas', '50030150', DEFAULT),
    ('10000000014', 'Nathan Oliveira Braga', '54240110', '410'),
    ('10000000015', 'Olívia Cardoso Maia', '53421080', '1102'),
    ('10000000016', 'Paulo César Figueiredo', '51030000', '65'),
    ('10000000017', 'Quézia Albuquerque Dias', '50720000', '201'),
    ('10000000018', 'Rafael Siqueira Prado', '52041000', DEFAULT),
    ('10000000019', 'Sabrina Melo Tavares', '50920000', '1304'),
    ('10000000020', 'Thiago Bezerra Coelho', '51130000', '88'),
    ('10000000021', 'Úrsula Campos Bastos', '50050000', '703'),
    ('10000000022', 'Vinícius Araújo Leite', '50030230', '1201'),
    ('10000000023', 'Wanessa Fontes Peixoto', '50710465', '44'),
    ('10000000024', 'Xavier Amaral Brito', '51020100', DEFAULT),
    ('10000000025', 'Yasmin Carvalho Neves', '52011010', '306'),
    ('10000000026', 'Zeca Pereira Guimarães', '53230630', '19'),
    ('10000000027', 'Amanda Rios Fagundes', '54410100', '902'),
    ('10000000028', 'Breno Castro Sampaio', '55016000', '57'),
    ('10000000029', 'Cecília Lins Wanderley', '50670901', DEFAULT),
    ('10000000030', 'Danilo Queiroz Bandeira', '51160000', '1502'),
    ('10000000031', 'Eduarda Sales Macedo', '52060000', '38'),
    ('10000000032', 'Felipe Torres Aragão', '50751330', '809'),
    ('20000000001', 'Adriana Fontoura Rangel', '50050000', '1201'),
    ('20000000002', 'Bernardo Ximenes Falcão', '50030230', '302'),
    ('20000000003', 'Cláudia Marinho Portela', '50710465', DEFAULT),
    ('20000000004', 'Davi Antunes Valadares', '51020100', '705'),
    ('20000000005', 'Eliana Prado Bittencourt', '52011010', '1404'),
    ('20000000006', 'Fernando Aguiar Mendonça', '53230630', '12'),
    ('20000000007', 'Graziela Couto Paiva', '54410100', '808'),
    ('20000000008', 'Heitor Vilela Drummond', '55016000', DEFAULT),
    ('20000000009', 'Ingrid Barreto Quintela', '50670901', '506'),
    ('20000000010', 'Joel Amâncio Pontes', '51160000', '1603'),
    ('20000000011', 'Kátia Soares Bulhões', '52060000', '71'),
    ('20000000012', 'Lucas Ferraz Galvão', '50751330', '904'),
    ('20000000013', 'Michele Tenório Aquino', '50030150', '208'),
    ('20000000014', 'Nelson Régis Bittar', '54240110', DEFAULT),
    ('20000000015', 'Otávio Lacerda Pimentel', '53421080', '1105'),
    ('20000000016', 'Priscila Vidal Escobar', '51030000', '66'),
    ('20000000017', 'Quirino Tavares Assunção', '50720000', '203'),
    ('20000000018', 'Renata Beltrão Cunha', '52041000', '1002'),
    ('20000000019', 'Sérgio Mourão Batista', '50920000', DEFAULT),
    ('20000000020', 'Tatiana Xavier Godoy', '51130000', '91'),
    ('20000000021', 'Ulisses Farias Caldas', '50050000', '704'),
    ('20000000022', 'Viviane Serpa Rangel', '50030230', '1205'),
    ('20000000023', 'Wagner Lobo Estrela', '50710465', '47'),
    ('20000000024', 'Yara Nogueira Lustosa', '51020100', DEFAULT),
    ('20000000025', 'Zilda Barros Espíndola', '52011010', '308'),
    ('20000000026', 'André Lustosa Pacheco', '53230630', '23'),
    ('20000000027', 'Bianca Cordeiro Vilar', '54410100', '907'),
    ('20000000028', 'Caio Sobral Fragoso', '55016000', '59'),
    ('20000000029', 'Débora Ipiranga Serra', '50670901', '511'),
    ('20000000030', 'Emanuel Tobias Guedes', '51160000', '1605');

INSERT INTO telefone (cpf, telefone) VALUES
    ('10000000001', '8199100001'),
    ('10000000002', '8199100002'),
    ('10000000003', '8199100003'),
    ('10000000004', '8199100004'),
    ('10000000005', '8199100005'),
    ('10000000006', '8199100006'),
    ('10000000007', '8199100007'),
    ('10000000008', '8199100008'),
    ('10000000009', '8199100009'),
    ('10000000010', '8199100010'),
    ('10000000011', '8199100011'),
    ('10000000012', '8199100012'),
    ('10000000013', '8199100013'),
    ('10000000014', '8199100014'),
    ('10000000015', '8199100015'),
    ('10000000016', '8199100016'),
    ('10000000017', '8199100017'),
    ('10000000018', '8199100018'),
    ('10000000019', '8199100019'),
    ('10000000020', '8199100020'),
    ('10000000021', '8199100021'),
    ('10000000022', '8199100022'),
    ('10000000023', '8199100023'),
    ('10000000024', '8199100024'),
    ('10000000025', '8199100025'),
    ('10000000026', '8199100026'),
    ('10000000027', '8199100027'),
    ('10000000028', '8199100028'),
    ('10000000029', '8199100029'),
    ('10000000030', '8199100030'),
    ('10000000031', '8199100031'),
    ('10000000032', '8199100032'),
    ('20000000001', '8199200001'),
    ('20000000002', '8199200002'),
    ('20000000003', '8199200003'),
    ('20000000004', '8199200004'),
    ('20000000005', '8199200005'),
    ('20000000006', '8199200006'),
    ('20000000007', '8199200007'),
    ('20000000008', '8199200008'),
    ('20000000009', '8199200009'),
    ('20000000010', '8199200010'),
    ('20000000011', '8199200011'),
    ('20000000012', '8199200012'),
    ('20000000013', '8199200013'),
    ('20000000014', '8199200014'),
    ('20000000015', '8199200015'),
    ('20000000016', '8199200016'),
    ('20000000017', '8199200017'),
    ('20000000018', '8199200018'),
    ('20000000019', '8199200019'),
    ('20000000020', '8199200020'),
    ('20000000021', '8199200021'),
    ('20000000022', '8199200022'),
    ('20000000023', '8199200023'),
    ('20000000024', '8199200024'),
    ('20000000025', '8199200025'),
    ('20000000026', '8199200026'),
    ('20000000027', '8199200027'),
    ('20000000028', '8199200028'),
    ('20000000029', '8199200029'),
    ('20000000030', '8199200030'),
    ('10000000001', '8132110001'),
    ('10000000004', '8132110002'),
    ('10000000008', '8132110003'),
    ('10000000013', '8132110004'),
    ('10000000019', '8132110005'),
    ('10000000026', '8132110006'),
    ('20000000002', '8132110007'),
    ('20000000009', '8132110008'),
    ('20000000016', '8132110009'),
    ('20000000023', '8132110010'),
    ('20000000030', '8132110011');

INSERT INTO convenio (codigo, nome) VALUES
    (1, 'Unimed Recife'),
    (2, 'Hapvida'),
    (3, 'Amil Saúde'),
    (4, 'Bradesco Saúde'),
    (5, 'SulAmérica Saúde'),
    (6, 'NotreDame Intermédica'),
    (7, 'Porto Seguro Saúde'),
    (8, 'Golden Cross'),
    (9, 'Cassi'),
    (10, 'Geap Saúde'),
    (11, 'Petrobras AMS'),
    (12, 'Assefaz'),
    (13, 'Capesesp'),
    (14, 'Camed Saúde'),
    (15, 'Postal Saúde'),
    (16, 'Saúde Caixa'),
    (17, 'Plan-Assiste'),
    (18, 'Life Empresarial'),
    (19, 'Prevent Senior'),
    (20, 'São Cristóvão Saúde'),
    (21, 'Unihosp'),
    (22, 'Medisanitas'),
    (23, 'Promed'),
    (24, 'Sami Saúde'),
    (25, 'Alice Saúde'),
    (26, 'Qsaúde'),
    (27, 'Omint Saúde'),
    (28, 'Care Plus'),
    (29, 'Allianz Saúde'),
    (30, 'Seguros Unimed'),
    (31, 'Ampla Saúde'),
    (32, 'Real Grandeza');

INSERT INTO paciente (cpf, codigo_convenio) VALUES
    ('10000000001', 1),
    ('10000000002', 2),
    ('10000000003', 3),
    ('10000000004', 4),
    ('10000000005', DEFAULT),
    ('10000000006', 6),
    ('10000000007', 7),
    ('10000000008', 8),
    ('10000000009', 9),
    ('10000000010', 10),
    ('10000000011', DEFAULT),
    ('10000000012', 12),
    ('10000000013', 13),
    ('10000000014', 14),
    ('10000000015', 15),
    ('10000000016', 16),
    ('10000000017', 17),
    ('10000000018', 18),
    ('10000000019', DEFAULT),
    ('10000000020', 20),
    ('10000000021', 21),
    ('10000000022', 22),
    ('10000000023', 23),
    ('10000000024', 24),
    ('10000000025', 25),
    ('10000000026', DEFAULT),
    ('10000000027', 27),
    ('10000000028', 28),
    ('10000000029', 29),
    ('10000000030', 30),
    ('10000000031', DEFAULT),
    ('10000000032', 32);

INSERT INTO alergia (cpf, alergia) VALUES
    ('10000000001', 'Dipirona'),
    ('10000000002', 'Penicilina'),
    ('10000000003', 'Lactose'),
    ('10000000004', 'Glúten'),
    ('10000000005', 'Frutos do mar'),
    ('10000000006', 'Amendoim'),
    ('10000000007', 'Poeira doméstica'),
    ('10000000008', 'Pelo de animais'),
    ('10000000009', 'Látex'),
    ('10000000010', 'Sulfas'),
    ('10000000011', 'Ibuprofeno'),
    ('10000000012', 'Ovo'),
    ('10000000013', 'Camarão'),
    ('10000000014', 'Pólen'),
    ('10000000015', 'Ácaros'),
    ('10000000016', 'Anti-inflamatórios'),
    ('10000000017', 'Iodo'),
    ('10000000018', 'Contraste iodado'),
    ('10000000019', 'Nenhuma conhecida'),
    ('10000000020', 'Picada de abelha'),
    ('10000000021', 'Corantes artificiais'),
    ('10000000022', 'Soja'),
    ('10000000023', 'Nenhuma conhecida'),
    ('10000000024', 'Carbamazepina'),
    ('10000000025', 'Nenhuma conhecida'),
    ('10000000026', 'Mofo'),
    ('10000000027', 'Níquel'),
    ('10000000028', 'Dipirona'),
    ('10000000029', 'Nenhuma conhecida'),
    ('10000000030', 'Penicilina'),
    ('10000000031', 'Ácaros'),
    ('10000000032', 'Lactose'),
    ('10000000001', 'Poeira doméstica'),
    ('10000000002', 'Ácaros'),
    ('10000000004', 'Camarão'),
    ('10000000006', 'Pólen'),
    ('10000000009', 'Ácaros'),
    ('10000000011', 'Dipirona'),
    ('10000000013', 'Amendoim'),
    ('10000000016', 'Sulfas'),
    ('10000000020', 'Mofo'),
    ('10000000022', 'Lactose'),
    ('10000000027', 'Pelo de animais'),
    ('10000000030', 'Iodo');

INSERT INTO medico (cpf, crm, especialidade) VALUES
    ('20000000001', '10001/PE', 'Cardiologia'),
    ('20000000002', '10002/PE', 'Dermatologia'),
    ('20000000003', '10003/PE', 'Endocrinologia'),
    ('20000000004', '10004/PE', 'Gastroenterologia'),
    ('20000000005', '10005/PE', 'Geriatria'),
    ('20000000006', '10006/PE', 'Ginecologia'),
    ('20000000007', '10007/PE', 'Neurologia'),
    ('20000000008', '10008/PE', 'Oftalmologia'),
    ('20000000009', '10009/PE', 'Ortopedia'),
    ('20000000010', '10010/PE', 'Otorrinolaringologia'),
    ('20000000011', '10011/PE', 'Pediatria'),
    ('20000000012', '10012/PE', 'Pneumologia'),
    ('20000000013', '10013/PE', 'Psiquiatria'),
    ('20000000014', '10014/PE', 'Reumatologia'),
    ('20000000015', '10015/PE', 'Urologia'),
    ('20000000016', '10016/PE', 'Infectologia'),
    ('20000000017', '10017/PE', 'Nefrologia'),
    ('20000000018', '10018/PE', 'Oncologia'),
    ('20000000019', '10019/PE', 'Hematologia'),
    ('20000000020', '10020/PE', DEFAULT),
    ('20000000021', '10021/PE', 'Cardiologia'),
    ('20000000022', '10022/PE', 'Dermatologia'),
    ('20000000023', '10023/PE', 'Endocrinologia'),
    ('20000000024', '10024/PE', 'Ginecologia'),
    ('20000000025', '10025/PE', 'Pediatria'),
    ('20000000026', '10026/PE', 'Psiquiatria'),
    ('20000000027', '10027/PE', 'Neurologia'),
    ('20000000028', '10028/PE', 'Ortopedia'),
    ('20000000029', '10029/PE', DEFAULT),
    ('20000000030', '10030/PE', 'Urologia');

INSERT INTO consulta (codigo, cpf_paciente, cpf_medico) VALUES
    (1, '10000000001', '20000000001'),
    (2, '10000000002', '20000000002'),
    (3, '10000000003', '20000000003'),
    (4, '10000000004', '20000000004'),
    (5, '10000000005', '20000000005'),
    (6, '10000000006', '20000000006'),
    (7, '10000000007', '20000000007'),
    (8, '10000000008', '20000000008'),
    (9, '10000000009', '20000000009'),
    (10, '10000000010', '20000000010'),
    (11, '10000000011', '20000000011'),
    (12, '10000000012', '20000000012'),
    (13, '10000000013', '20000000013'),
    (14, '10000000014', '20000000014'),
    (15, '10000000015', '20000000015'),
    (16, '10000000016', '20000000016'),
    (17, '10000000017', '20000000017'),
    (18, '10000000018', '20000000018'),
    (19, '10000000019', '20000000019'),
    (20, '10000000020', '20000000020'),
    (21, '10000000021', '20000000021'),
    (22, '10000000022', '20000000022'),
    (23, '10000000023', '20000000023'),
    (24, '10000000024', '20000000024'),
    (25, '10000000025', '20000000025'),
    (26, '10000000026', '20000000026'),
    (27, '10000000027', '20000000027'),
    (28, '10000000028', '20000000028'),
    (29, '10000000029', '20000000029'),
    (30, '10000000030', '20000000030'),
    (31, '10000000001', '20000000001'),
    (32, '10000000002', '20000000002'),
    (33, '10000000003', '20000000003'),
    (34, '10000000004', '20000000004'),
    (35, '10000000005', '20000000005'),
    (36, '10000000006', '20000000006'),
    (37, '10000000007', '20000000007'),
    (38, '10000000008', '20000000008'),
    (39, '10000000009', '20000000009'),
    (40, '10000000010', '20000000010'),
    (41, '10000000011', '20000000011'),
    (42, '10000000012', '20000000012'),
    (43, '10000000013', '20000000013'),
    (44, '10000000014', '20000000014'),
    (45, '10000000015', '20000000015'),
    (46, '10000000016', '20000000016'),
    (47, '10000000017', '20000000017'),
    (48, '10000000018', '20000000018'),
    (49, '10000000019', '20000000019'),
    (50, '10000000020', '20000000020'),
    (51, '10000000021', '20000000021'),
    (52, '10000000022', '20000000022'),
    (53, '10000000023', '20000000023'),
    (54, '10000000024', '20000000024'),
    (55, '10000000025', '20000000025'),
    (56, '10000000026', '20000000026'),
    (57, '10000000027', '20000000027'),
    (58, '10000000028', '20000000028'),
    (59, '10000000029', '20000000029'),
    (60, '10000000030', '20000000030'),
    (61, '10000000001', '20000000001'),
    (62, '10000000002', '20000000002'),
    (63, '10000000003', '20000000003'),
    (64, '10000000004', '20000000004');

INSERT INTO retorno (codigo_consulta_origem, codigo_consulta_retorno) VALUES
    (1, 31),
    (2, 32),
    (3, 33),
    (4, 34),
    (5, 35),
    (6, 36),
    (7, 37),
    (8, 38),
    (9, 39),
    (10, 40),
    (11, 41),
    (12, 42),
    (13, 43),
    (14, 44),
    (15, 45),
    (16, 46),
    (17, 47),
    (18, 48),
    (19, 49),
    (20, 50),
    (21, 51),
    (22, 52),
    (23, 53),
    (24, 54),
    (25, 55),
    (26, 56),
    (27, 57),
    (28, 58),
    (29, 59),
    (30, 60),
    (31, 61),
    (32, 62),
    (33, 63),
    (34, 64);

INSERT INTO prescricao (codigo_consulta, nome) VALUES
    (1, 'Receita de antibiótico'),
    (2, 'Receita de uso contínuo'),
    (3, 'Receita analgésica'),
    (4, 'Receita anti-hipertensiva'),
    (5, 'Receita para controle glicêmico'),
    (6, 'Receita antialérgica'),
    (7, DEFAULT),
    (8, 'Receita anti-inflamatória'),
    (9, 'Receita para via respiratória'),
    (10, 'Receita de reposição hormonal'),
    (11, 'Receita de antibiótico'),
    (12, 'Receita de uso contínuo'),
    (13, 'Receita analgésica'),
    (14, DEFAULT),
    (15, 'Receita para controle glicêmico'),
    (16, 'Receita antialérgica'),
    (17, 'Receita gastroprotetora'),
    (18, 'Receita anti-inflamatória'),
    (19, 'Receita para via respiratória'),
    (20, 'Receita de reposição hormonal'),
    (21, DEFAULT),
    (22, 'Receita de uso contínuo'),
    (23, 'Receita analgésica'),
    (24, 'Receita anti-hipertensiva'),
    (25, 'Receita para controle glicêmico'),
    (26, 'Receita antialérgica'),
    (27, 'Receita gastroprotetora'),
    (28, DEFAULT),
    (29, 'Receita para via respiratória'),
    (30, 'Receita de reposição hormonal'),
    (31, 'Receita de antibiótico'),
    (32, 'Receita de uso contínuo'),
    (33, 'Receita analgésica'),
    (34, 'Receita anti-hipertensiva'),
    (35, DEFAULT),
    (36, 'Receita antialérgica'),
    (37, 'Receita gastroprotetora'),
    (38, 'Receita anti-inflamatória'),
    (39, 'Receita para via respiratória'),
    (40, 'Receita de reposição hormonal'),
    (41, 'Receita de antibiótico'),
    (42, DEFAULT),
    (43, 'Receita analgésica'),
    (44, 'Receita anti-hipertensiva'),
    (45, 'Receita para controle glicêmico'),
    (46, 'Receita antialérgica'),
    (47, 'Receita gastroprotetora'),
    (48, 'Receita anti-inflamatória'),
    (49, DEFAULT),
    (50, 'Receita de reposição hormonal'),
    (51, 'Receita de antibiótico'),
    (52, 'Receita de uso contínuo'),
    (53, 'Receita analgésica'),
    (54, 'Receita anti-hipertensiva'),
    (55, 'Receita para controle glicêmico'),
    (56, DEFAULT),
    (57, 'Receita gastroprotetora'),
    (58, 'Receita anti-inflamatória'),
    (59, 'Receita para via respiratória'),
    (60, 'Receita de reposição hormonal'),
    (61, 'Receita de antibiótico'),
    (62, 'Receita de uso contínuo'),
    (63, DEFAULT),
    (64, 'Receita anti-hipertensiva');

INSERT INTO medicamento (codigo, nome) VALUES
    (1, 'Amoxicilina 500mg'),
    (2, 'Dipirona Sódica 500mg'),
    (3, 'Paracetamol 750mg'),
    (4, 'Ibuprofeno 600mg'),
    (5, 'Omeprazol 20mg'),
    (6, 'Losartana Potássica 50mg'),
    (7, 'Metformina 850mg'),
    (8, 'Atenolol 25mg'),
    (9, 'Sinvastatina 20mg'),
    (10, 'Azitromicina 500mg'),
    (11, 'Cefalexina 500mg'),
    (12, 'Prednisona 20mg'),
    (13, 'Dexametasona 4mg'),
    (14, 'Loratadina 10mg'),
    (15, 'Cetirizina 10mg'),
    (16, 'Salbutamol Spray 100mcg'),
    (17, 'Budesonida 200mcg'),
    (18, 'Enalapril 10mg'),
    (19, 'Hidroclorotiazida 25mg'),
    (20, 'Captopril 25mg'),
    (21, 'Ranitidina 150mg'),
    (22, 'Pantoprazol 40mg'),
    (23, 'Clonazepam 2mg'),
    (24, 'Sertralina 50mg'),
    (25, 'Fluoxetina 20mg'),
    (26, 'Levotiroxina 50mcg'),
    (27, 'Insulina NPH 100UI'),
    (28, 'Glibenclamida 5mg'),
    (29, 'Diclofenaco Sódico 50mg'),
    (30, 'Nimesulida 100mg'),
    (31, 'Ciprofloxacino 500mg'),
    (32, 'Bromoprida 10mg');

INSERT INTO contem (codigo_consulta, codigo_medicamento) VALUES
    (1, 1),
    (1, 11),
    (2, 2),
    (3, 3),
    (3, 13),
    (4, 4),
    (5, 5),
    (5, 15),
    (6, 6),
    (7, 7),
    (7, 17),
    (8, 8),
    (9, 9),
    (9, 19),
    (10, 10),
    (11, 11),
    (11, 21),
    (12, 12),
    (13, 13),
    (13, 23),
    (14, 14),
    (15, 15),
    (15, 25),
    (16, 16),
    (17, 17),
    (17, 27),
    (18, 18),
    (19, 19),
    (19, 29),
    (20, 20),
    (21, 21),
    (21, 31),
    (22, 22),
    (23, 23),
    (23, 1),
    (24, 24),
    (25, 25),
    (25, 3),
    (26, 26),
    (27, 27),
    (27, 5),
    (28, 28),
    (29, 29),
    (29, 7),
    (30, 30),
    (31, 31),
    (31, 9),
    (32, 32),
    (33, 1),
    (33, 11),
    (34, 2),
    (35, 3),
    (35, 13),
    (36, 4),
    (37, 5),
    (37, 15),
    (38, 6),
    (39, 7),
    (39, 17),
    (40, 8),
    (41, 9),
    (41, 19),
    (42, 10),
    (43, 11),
    (43, 21),
    (44, 12),
    (45, 13),
    (45, 23),
    (46, 14),
    (47, 15),
    (47, 25),
    (48, 16),
    (49, 17),
    (49, 27),
    (50, 18),
    (51, 19),
    (51, 29),
    (52, 20),
    (53, 21),
    (53, 31),
    (54, 22),
    (55, 23),
    (55, 1),
    (56, 24),
    (57, 25),
    (57, 3),
    (58, 26),
    (59, 27),
    (59, 5),
    (60, 28),
    (61, 29),
    (61, 7),
    (62, 30),
    (63, 31),
    (63, 9),
    (64, 32);

INSERT INTO exame (codigo, nome) VALUES
    (1, 'Hemograma completo'),
    (2, 'Glicemia de jejum'),
    (3, 'Colesterol total e frações'),
    (4, 'Triglicerídeos'),
    (5, 'TSH'),
    (6, 'T4 livre'),
    (7, 'Creatinina sérica'),
    (8, 'Ureia sérica'),
    (9, 'Ácido úrico'),
    (10, 'TGO (AST)'),
    (11, 'TGP (ALT)'),
    (12, 'Urina tipo I (EAS)'),
    (13, 'Parasitológico de fezes'),
    (14, 'Eletrocardiograma'),
    (15, 'Ecocardiograma'),
    (16, 'Teste ergométrico'),
    (17, 'Raio-X de tórax'),
    (18, 'Ultrassonografia abdominal'),
    (19, 'Ultrassonografia de tireoide'),
    (20, 'Tomografia computadorizada de crânio'),
    (21, 'Ressonância magnética de joelho'),
    (22, 'Densitometria óssea'),
    (23, 'Mamografia'),
    (24, 'Endoscopia digestiva alta'),
    (25, 'Colonoscopia'),
    (26, 'Espirometria'),
    (27, 'Audiometria'),
    (28, 'Hemoglobina glicada'),
    (29, 'Vitamina D (25-OH)'),
    (30, 'Ferritina sérica'),
    (31, 'PCR ultrassensível'),
    (32, 'Coagulograma');

INSERT INTO solicita (codigo_consulta, codigo_exame) VALUES
    (1, 1),
    (1, 17),
    (2, 2),
    (2, 18),
    (3, 3),
    (3, 19),
    (4, 4),
    (4, 20),
    (5, 5),
    (5, 21),
    (6, 6),
    (6, 22),
    (7, 7),
    (7, 23),
    (8, 8),
    (8, 24),
    (9, 9),
    (9, 25),
    (10, 10),
    (10, 26),
    (11, 11),
    (12, 12),
    (13, 13),
    (14, 14),
    (15, 15),
    (16, 16),
    (17, 17),
    (18, 18),
    (19, 19),
    (20, 20),
    (21, 21),
    (22, 22),
    (23, 23),
    (24, 24),
    (25, 25),
    (26, 26),
    (27, 27),
    (28, 28),
    (29, 29),
    (30, 30),
    (31, 31),
    (32, 32),
    (33, 1),
    (34, 2),
    (35, 3),
    (36, 4),
    (37, 5),
    (38, 6),
    (39, 7),
    (40, 8),
    (41, 9),
    (42, 10),
    (43, 11),
    (44, 12),
    (45, 13),
    (46, 14),
    (47, 15),
    (48, 16),
    (49, 17),
    (50, 18),
    (51, 19),
    (52, 20),
    (53, 21),
    (54, 22),
    (55, 23),
    (56, 24),
    (57, 25),
    (58, 26),
    (59, 27),
    (60, 28),
    (61, 29),
    (62, 30),
    (63, 31),
    (64, 32);



-- >>>>>>>>>>>>>>>>>>>> sql/04_indices.sql <<<<<<<<<<<<<<<<<<<<
USE prontuario_medico;
CREATE INDEX idx_alergia_descricao
    ON alergia (alergia);

CREATE INDEX idx_medico_especialidade
    ON medico (especialidade);

CREATE INDEX idx_pessoa_nome
    ON pessoa (nome);




-- >>>>>>>>>>>>>>>>>>>> sql/04_visoes.sql <<<<<<<<<<<<<<<<<<<<
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





-- >>>>>>>>>>>>>>>>>>>> sql/05_funcoes.sql <<<<<<<<<<<<<<<<<<<<
USE prontuario_medico;

DROP FUNCTION IF EXISTS fn_classificar_polifarmacia;
DROP FUNCTION IF EXISTS fn_paciente_alergico_a_medicamento;

DELIMITER $$

CREATE FUNCTION fn_classificar_polifarmacia(p_cpf CHAR(11))
RETURNS VARCHAR(40)
READS SQL DATA
BEGIN
    DECLARE v_qtd INT DEFAULT 0;

    SELECT COUNT(DISTINCT ct.codigo_medicamento)
      INTO v_qtd
      FROM consulta c
      JOIN contem   ct ON ct.codigo_consulta = c.codigo
     WHERE c.cpf_paciente = p_cpf;

    IF v_qtd >= 5 THEN
        RETURN 'Polifarmácia — revisar medicação';
    ELSEIF v_qtd >= 3 THEN
        RETURN 'Atenção — acompanhar';
    ELSEIF v_qtd >= 1 THEN
        RETURN 'Regular';
    ELSE
        RETURN 'Sem medicação prescrita';
    END IF;
END$$


CREATE FUNCTION fn_paciente_alergico_a_medicamento(p_cpf CHAR(11),
                                                   p_codigo_medicamento INT)
RETURNS TINYINT(1)
READS SQL DATA
BEGIN
    DECLARE v_nome_medicamento VARCHAR(100);

    SELECT nome
      INTO v_nome_medicamento
      FROM medicamento
     WHERE codigo = p_codigo_medicamento;

    IF v_nome_medicamento IS NULL THEN
        RETURN 0;
    END IF;

    RETURN EXISTS (
        SELECT 1
          FROM alergia a
         WHERE a.cpf = p_cpf
           AND (   v_nome_medicamento LIKE CONCAT(a.alergia, '%')
                OR (a.alergia = 'Anti-inflamatórios'
                    AND v_nome_medicamento REGEXP '^(Ibuprofeno|Diclofenaco|Nimesulida)')
                OR (a.alergia = 'Penicilina'
                    AND v_nome_medicamento REGEXP '^(Amoxicilina)'))
    );
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- Exemplos de uso
-- ---------------------------------------------------------------------
-- Classificação de todos os pacientes (aceita qualquer filtro/ordenação):
--   SELECT p.nome, fn_classificar_polifarmacia(pac.cpf) AS situacao
--     FROM paciente pac JOIN pessoa p ON p.cpf = pac.cpf
--    ORDER BY situacao, p.nome;
--
-- Pacientes em polifarmácia:
--   SELECT p.nome FROM paciente pac JOIN pessoa p ON p.cpf = pac.cpf
--    WHERE fn_classificar_polifarmacia(pac.cpf) LIKE 'Polifarmácia%';
--
-- Conflito de alergia (paciente 10000000001 é alérgico a Dipirona;
-- medicamento 2 = Dipirona Sódica 500mg  ->  1; medicamento 3 = Paracetamol -> 0):
--   SELECT fn_paciente_alergico_a_medicamento('10000000001', 2) AS dipirona,
--          fn_paciente_alergico_a_medicamento('10000000001', 3) AS paracetamol;
--
-- Alergia a classe (paciente 10000000016 é alérgico a Anti-inflamatórios;
-- medicamento 29 = Diclofenaco -> 1):
--   SELECT fn_paciente_alergico_a_medicamento('10000000016', 29);


-- >>>>>>>>>>>>>>>>>>>> sql/05_procedimentos.sql <<<<<<<<<<<<<<<<<<<<
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



-- >>>>>>>>>>>>>>>>>>>> sql/05_triggers.sql <<<<<<<<<<<<<<<<<<<<
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





-- >>>>>>>>>>>>>>>>>>>> sql/06_dashboard.sql <<<<<<<<<<<<<<<<<<<<
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


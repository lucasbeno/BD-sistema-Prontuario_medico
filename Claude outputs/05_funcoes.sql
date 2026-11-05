-- =====================================================================
-- ETAPA 05 — FUNÇÕES
-- Sistema de Prontuário Médico (Clínica VidaPlena) — MySQL 8+
-- Executar DEPOIS da criação/inserção e da Etapa 04.
-- Ordem da Etapa 05: 05_funcoes.sql -> 05_procedimentos.sql -> 05_triggers.sql
--   (o trigger de alergia usa a função 2 deste arquivo)
-- =====================================================================
USE prontuario_medico;

DROP FUNCTION IF EXISTS fn_classificar_polifarmacia;
DROP FUNCTION IF EXISTS fn_paciente_alergico_a_medicamento;

DELIMITER $$


-- =====================================================================
-- FUNÇÃO 1 — fn_classificar_polifarmacia(cpf do paciente)
--
-- Justificativa semântica:
-- Quanto mais medicamentos diferentes um paciente recebe, maior o risco de
-- interação e de efeito colateral; a partir de 5 a literatura chama de
-- POLIFARMÁCIA e o paciente deve passar por revisão da medicação (a mesma
-- regra usada na Consulta 4 da Etapa 04). A função devolve esse rótulo
-- clínico para qualquer paciente, de modo que a recepção, o dashboard e as
-- consultas usem SEMPRE o mesmo critério, em vez de cada um repetir a
-- contagem e os limites.
--
-- Estrutura condicional: IF / ELSEIF / ELSE com quatro faixas.
--   >= 5 medicamentos distintos  -> 'Polifarmácia — revisar medicação'
--   3 ou 4                       -> 'Atenção — acompanhar'
--   1 ou 2                       -> 'Regular'
--   nenhum                       -> 'Sem medicação prescrita'
-- =====================================================================
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


-- =====================================================================
-- FUNÇÃO 2 — fn_paciente_alergico_a_medicamento(cpf, código do medicamento)
--
-- Justificativa semântica:
-- Prescrever um medicamento a quem tem alergia a ele é o erro de segurança
-- mais grave que um prontuário deve evitar. A alergia é cadastrada pelo
-- nome da substância ou da classe ('Dipirona', 'Anti-inflamatórios',
-- 'Penicilina'), enquanto o medicamento tem nome comercial com dose
-- ('Dipirona Sódica 500mg', 'Diclofenaco Sódico 50mg', 'Amoxicilina 500mg').
-- A função faz essa ponte e devolve 1 (conflito) ou 0 (sem conflito):
--   - nome da alergia é o começo do nome do medicamento
--       Dipirona    -> Dipirona Sódica 500mg
--       Ibuprofeno  -> Ibuprofeno 600mg
--   - alergia a CLASSE cobre todos os medicamentos da classe
--       Anti-inflamatórios -> Ibuprofeno, Diclofenaco, Nimesulida
--       Penicilina         -> Amoxicilina
-- É usada pelo trigger trg_contem_bloqueia_alergia (05_triggers.sql) e
-- serve também para consultas de auditoria.
-- =====================================================================
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

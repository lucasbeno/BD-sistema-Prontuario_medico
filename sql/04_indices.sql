USE prontuario_medico;
.
CREATE INDEX idx_alergia_descricao
    ON alergia (alergia);

CREATE INDEX idx_medico_especialidade
    ON medico (especialidade);

CREATE INDEX idx_pessoa_nome
    ON pessoa (nome);


-- =========================================================
-- PrintAG — 008: Schema Base v2
-- Cria novo schema sem afetar tabelas legadas (001-007).
-- =========================================================

-- ---------- 0. Extensão + Helper ----------

CREATE EXTENSION IF NOT EXISTS unaccent;

-- norm(): normalização para joins text-sem-acento
-- Usada tanto em GENERATED columns quanto no MV.
-- LANGUAGE plpgsql (não sql) para evitar inlining: se fosse sql, o PostgreSQL
-- expandiria o corpo e veria o unaccent() STABLE, causando erro 42P17 nas
-- GENERATED columns que chamam norm().
CREATE OR REPLACE FUNCTION norm(t TEXT)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
  STRICT
AS $$
BEGIN
  RETURN lower(unaccent(trim(t)));
END;
$$;

-- =========================================================
-- TABELAS ESPELHO (flat mirrors dos CSVs — sem FKs)
-- =========================================================

-- printag_apontamentos
-- Espelho de "Apontamentos Máquinas 2025 e 2026.csv"
CREATE TABLE IF NOT EXISTS printag_apontamentos (
  id             BIGSERIAL   PRIMARY KEY,
  equipamento    TEXT        NOT NULL,
  tipo_apontam   TEXT        NOT NULL,
  motivo         TEXT,
  inicio         TIMESTAMPTZ NOT NULL,
  fim            TIMESTAMPTZ,
  nro_os         TEXT,
  produzido      INTEGER     NOT NULL DEFAULT 0,
  titulo_produto TEXT,
  nome_cliente   TEXT,
  operador       TEXT,
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- chave: concatenação norm(tipo_apontam)||norm(motivo) — igual ao campo 'chave' do CSV 4.
  -- Usada para JOIN direto com printiag_classificacao.chave na MV.
  chave          TEXT        GENERATED ALWAYS AS (
                   norm(tipo_apontam) || norm(COALESCE(motivo, ''))
                 ) STORED,
  CONSTRAINT chk_pa_inicio_fim CHECK (fim IS NULL OR fim >= inicio)
);

CREATE INDEX IF NOT EXISTS idx_pa_equip    ON printag_apontamentos (equipamento);
CREATE INDEX IF NOT EXISTS idx_pa_inicio   ON printag_apontamentos (inicio DESC);
CREATE INDEX IF NOT EXISTS idx_pa_nro_os   ON printag_apontamentos (nro_os);
CREATE INDEX IF NOT EXISTS idx_pa_tipo     ON printag_apontamentos (tipo_apontam);
CREATE INDEX IF NOT EXISTS idx_pa_operador ON printag_apontamentos (operador);
CREATE INDEX IF NOT EXISTS idx_pa_chave    ON printag_apontamentos (chave);

-- printag_acabamentos
-- Espelho de "Tipo Acabamento - MM.csv"
CREATE TABLE IF NOT EXISTS printag_acabamentos (
  id                BIGSERIAL   PRIMARY KEY,
  nro_os            TEXT        NOT NULL,
  equipamento_plan  TEXT,
  nome_cliente      TEXT,
  descricao_servico TEXT,
  tipo_acabamento   TEXT,
  hrs_pcp           NUMERIC(8,2),
  quantidade        INTEGER,
  ini_calculado     DATE,
  fim_calculado     DATE,
  atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pacab_os   ON printag_acabamentos (nro_os);
CREATE INDEX IF NOT EXISTS idx_pacab_tipo ON printag_acabamentos (tipo_acabamento);

-- printag_facas
-- Espelho de "Levantamento Metros Lineares e Montagem.csv"
CREATE TABLE IF NOT EXISTS printag_facas (
  id            BIGSERIAL   PRIMARY KEY,
  nro_os        TEXT        NOT NULL,
  faca          TEXT,
  lado_1        NUMERIC(10,2),
  lado_2        NUMERIC(10,2),
  montagem      INTEGER,
  medida_total  TEXT,
  l1_total      NUMERIC(10,2),
  l2_total      NUMERIC(10,2),
  fto_final     INTEGER,
  fto_impr      INTEGER,
  l1_substrato  NUMERIC(10,2),
  l2_substrato  NUMERIC(10,2),
  l1_corte      NUMERIC(10,2),
  l2_corte      NUMERIC(10,2),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pfacas_os ON printag_facas (nro_os);

-- =========================================================
-- DIMENSÕES / AUXILIARES (com IDs e seeds)
-- =========================================================

-- printiag_maquinas
-- Cadastro de equipamentos. nome_norm é gerado para lookup via norm().
CREATE TABLE IF NOT EXISTS printiag_maquinas (
  id          SERIAL  PRIMARY KEY,
  nome_maquina TEXT   NOT NULL,
  area         TEXT   NOT NULL,
  velocidade   NUMERIC NOT NULL DEFAULT 0,
  nome_norm    TEXT   GENERATED ALWAYS AS (norm(nome_maquina)) STORED,
  CONSTRAINT uq_pmaq_nome_norm UNIQUE (nome_norm)
);

INSERT INTO printiag_maquinas (nome_maquina, area, velocidade) VALUES
  ('Coladeira Novafold',   'Acabamento', 25000),
  ('Coladeira Ambition',   'Acabamento', 25000),
  ('Coladeira Expertfold', 'Acabamento', 80000)
ON CONFLICT (nome_norm) DO UPDATE
  SET area       = EXCLUDED.area,
      velocidade = EXCLUDED.velocidade;

-- printiag_classificacao
-- De-para chave (raw) → classificação de perda OEE.
-- chave = concatenação raw do tipo_apontam + motivo, igual ao campo 'Chave' do Excel.
-- chave_norm = norm(chave), usado para JOIN eficiente com printag_apontamentos.chave.
-- A MV usa LATERAL + LIMIT 1 para evitar duplicatas quando variantes de grafia
-- (ex: 'OciosoRefeicao' e 'OciosoRefeição') normalizam para o mesmo chave_norm.
CREATE TABLE IF NOT EXISTS printiag_classificacao (
  id                  SERIAL PRIMARY KEY,
  chave               TEXT   NOT NULL,           -- raw, igual ao Excel (ex: 'OciosoRefeição')
  tipo_apontam        TEXT   NOT NULL,
  motivo              TEXT   NOT NULL DEFAULT '',
  classificacao_perda TEXT   NOT NULL,
  atuacao             TEXT   NOT NULL,
  nivel_atuacao       TEXT,
  tipo_norm           TEXT   GENERATED ALWAYS AS (norm(tipo_apontam)) STORED,
  motivo_norm         TEXT   GENERATED ALWAYS AS (norm(motivo))       STORED,
  chave_norm          TEXT   GENERATED ALWAYS AS (norm(chave))        STORED,
  CONSTRAINT uq_pclass_chave UNIQUE (chave)
);

-- Índice principal: lookup por chave_norm na MV
CREATE INDEX IF NOT EXISTS idx_pclass_chave_norm ON printiag_classificacao (chave_norm);
CREATE INDEX IF NOT EXISTS idx_pclass_norm       ON printiag_classificacao (tipo_norm, motivo_norm);

-- Seed — todas as 83 linhas do classificacao_tb.xlsx (fonte de verdade).
-- Filtra por chave_norm (não só chave): numa reaplicação (022+ já rodou e
-- deduplicou), o dedup já removeu a variante perdedora, e reinseri-la
-- violaria uq_pclass_chave_norm sem que o ON CONFLICT (chave) a detectasse
-- (chave arbiter diferente do índice que de fato colide).
INSERT INTO printiag_classificacao
  (chave, tipo_apontam, motivo, classificacao_perda, atuacao, nivel_atuacao)
SELECT v.chave, v.tipo_apontam, v.motivo, v.classificacao_perda, v.atuacao, v.nivel_atuacao
FROM (VALUES
  ('OciosoSem Apontamento', 'Ocioso', 'Sem Apontamento', 'Sem Apontamento', 'Sem Apontamento', 'Gerencial'),
  ('OciosoFalta de Servico', 'Ocioso', 'Falta de Servico', 'Sem Serviço', 'Gerencial', 'Gerencial'),
  ('OciosoManutencao Preventiva', 'Ocioso', 'Manutencao Preventiva', 'Manutenção Preventiva', 'Gerencial', 'Gerencial'),
  ('OciosoManutenção Preventiva', 'Ocioso', 'Manutenção Preventiva', 'Manutenção Preventiva', 'Gerencial', 'Gerencial'),
  ('OciosoFalta de Operador', 'Ocioso', 'Falta de Operador', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoRefeicao', 'Ocioso', 'Refeicao', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoRefeição', 'Ocioso', 'Refeição', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoLimpeza', 'Ocioso', 'Limpeza', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoPreparacao de Maquina', 'Ocioso', 'Preparacao de Maquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoPreparação de Máquina', 'Ocioso', 'Preparação de Máquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoFalta de Papel', 'Ocioso', 'Falta de Papel', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoGravacao Chapa Pre Impressao', 'Ocioso', 'Gravacao Chapa Pre Impressao', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoGravação Chapa Pré Impressão', 'Ocioso', 'Gravação Chapa Pré Impressão', 'Aguardando', 'Área', 'Liderança'),
  ('Acerto', 'Acerto', '', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoLavagem', 'Ocioso', 'Lavagem', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoGravacao Chapa Impressao', 'Ocioso', 'Gravacao Chapa Impressao', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoOutros', 'Ocioso', 'Outros', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoPreparacao de Tinta', 'Ocioso', 'Preparacao de Tinta', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoTroca de Lixas', 'Ocioso', 'Troca de Lixas', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoManutencao Corretiva', 'Ocioso', 'Manutencao Corretiva', 'Manutenção Corretiva', 'Área', 'Liderança'),
  ('OciosoManutenção Corretiva', 'Ocioso', 'Manutenção Corretiva', 'Manutenção Corretiva', 'Área', 'Liderança'),
  ('OciosoQuebra', 'Ocioso', 'Quebra', 'Manutenção Corretiva', 'Área', 'Liderança'),
  ('Producao', 'Producao', '', 'Virando', 'Virando', 'Operacional'),
  ('Produção', 'Produção', '', 'Virando', 'Virando', 'Operacional'),
  ('OciosoMáquina Quebrada', 'Ocioso', 'Máquina Quebrada', 'Manutenção Corretiva', 'Área', 'Liderança'),
  ('OciosoReunião/Palestra', 'Ocioso', 'Reunião/Palestra', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoAguardando Aprovacao', 'Ocioso', 'Aguardando Aprovacao', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoSem trabalho/ocioso', 'Ocioso', 'Sem trabalho/ocioso', 'Sem Serviço', 'Gerencial', 'Gerencial'),
  ('OciosoTroca de Serviço', 'Ocioso', 'Troca de Serviço', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoTroca de Operador', 'Ocioso', 'Troca de Operador', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoAguardando Impressão Off-Set', 'Ocioso', 'Aguardando Impressão Off-Set', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoGravação Chapa Impressão', 'Ocioso', 'Gravação Chapa Impressão', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoOperadores em Outra Maquina', 'Ocioso', 'Operadores em Outra Maquina', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoFalta de Servico Destacado', 'Ocioso', 'Falta de Servico Destacado', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoLiberacao de Maquina', 'Ocioso', 'Liberacao de Maquina', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoColagem Manual', 'Ocioso', 'Colagem Manual', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('ProducaoProducao Produto Piloto', 'Producao', 'Producao Produto Piloto', 'Virando', 'Virando', 'Operacional'),
  ('OciosoAguardando Triagem', 'Ocioso', 'Aguardando Triagem', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoAguardando Corte e Vinco', 'Ocioso', 'Aguardando Corte e Vinco', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoLimpeza da Maquina', 'Ocioso', 'Limpeza da Maquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoProducao Produto Piloto', 'Ocioso', 'Producao Produto Piloto', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoAguardando Liberacao CQ', 'Ocioso', 'Aguardando Liberacao CQ', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoTroca de Servico', 'Ocioso', 'Troca de Servico', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoLimpeza do Coleiro', 'Ocioso', 'Limpeza do Coleiro', 'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoReuniao/Palestra', 'Ocioso', 'Reuniao/Palestra', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Ocioso01o Entrada Concluida', 'Ocioso', '01o Entrada Concluida', 'Virando', 'Virando', 'Operacional'),
  ('OciosoAguardando Lib. de Braille', 'Ocioso', 'Aguardando Lib. de Braille', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoAguardando Impressao Off-Set', 'Ocioso', 'Aguardando Impressao Off-Set', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoFim expediente/Intervalo', 'Ocioso', 'Fim expediente/Intervalo', 'Sem Tripulação', 'Sem Apontamento', 'Gerencial'),
  ('OciosoSem Tripulacao', 'Ocioso', 'Sem Tripulacao', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Producao01o Entrada Concluida', 'Producao', '01o Entrada Concluida', 'Virando', 'Virando', 'Operacional'),
  ('OciosoTeste de Material', 'Ocioso', 'Teste de Material', 'Sem Serviço', 'Gerencial', 'Gerencial'),
  ('OciosoFalta de Energia', 'Ocioso', 'Falta de Energia', 'Sem Serviço', 'Gerencial', 'Gerencial'),
  ('OciosoMaquina Quebrada', 'Ocioso', 'Maquina Quebrada', 'Manutenção Corretiva', 'Área', 'Liderança'),
  ('OciosoSem Tripulação', 'Ocioso', 'Sem Tripulação', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoOperadores em Outra Máquina', 'Ocioso', 'Operadores em Outra Máquina', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoLiberação de Máquina', 'Ocioso', 'Liberação de Máquina', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoFalta de Serviço Destacado', 'Ocioso', 'Falta de Serviço Destacado', 'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoLimpeza da Máquina', 'Ocioso', 'Limpeza da Máquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('Ocioso01º Entrada Concluída', 'Ocioso', '01º Entrada Concluída', 'Acerto', 'Acerto', 'Operacional'),
  ('OciosoAguardando Liberação CQ', 'Ocioso', 'Aguardando Liberação CQ', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoEquipe deslocada para AF', 'Ocioso', 'Equipe deslocada para AF', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Ocioso  Operadores em Outra Máquina', 'Ocioso', 'Operadores em Outra Máquina', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Ocioso  Refeição', 'Ocioso', 'Refeição', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Ocioso  Preparação de Máquina', 'Ocioso', 'Preparação de Máquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('Ocioso  Sem trabalho/ocioso', 'Ocioso', 'Sem trabalho/ocioso', 'Sem Serviço', 'Gerencial', 'Gerencial'),
  ('Ocioso  Troca de Serviço', 'Ocioso', 'Troca de Serviço', 'Acerto', 'Acerto', 'Operacional'),
  ('Ocioso  Sem Tripulação', 'Ocioso', 'Sem Tripulação', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('Ocioso  Liberação de Máquina', 'Ocioso', 'Liberação de Máquina', 'Acerto', 'Acerto', 'Operacional'),
  ('Ocioso  Falta de Serviço Destacado', 'Ocioso', 'Falta de Serviço Destacado', 'Aguardando', 'Área', 'Liderança'),
  ('Ocioso  Aguardando Corte e Vinco', 'Ocioso', 'Aguardando Corte e Vinco', 'Aguardando', 'Área', 'Liderança'),
  ('Ocioso  Limpeza da Máquina', 'Ocioso', 'Limpeza da Máquina', 'Operacional Planejado', 'Área', 'Liderança'),
  ('Ocioso  Aguardando Liberação CQ', 'Ocioso', 'Aguardando Liberação CQ', 'Aguardando', 'Área', 'Liderança'),
  ('Ocioso  Aguardando Triagem', 'Ocioso', 'Aguardando Triagem', 'Aguardando', 'Área', 'Liderança'),
  ('Ocioso  01º Entrada Concluída', 'Ocioso', '01º Entrada Concluída', 'Acerto', 'Acerto', 'Operacional'),
  ('Ocioso  Equipe deslocada para AF', 'Ocioso', 'Equipe deslocada para AF', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoAcerto Produto Piloto', 'Ocioso', 'Acerto Produto Piloto', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoEq deslocada para outra máq', 'Ocioso', 'Eq deslocada para outra máq', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoServiços Manuais', 'Ocioso', 'Serviços Manuais', 'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoOrganização de Setor', 'Ocioso', 'Organização de Setor', 'Operacional Planejado', 'Área', 'Liderança')
) AS v(chave, tipo_apontam, motivo, classificacao_perda, atuacao, nivel_atuacao)
WHERE NOT EXISTS (
  SELECT 1 FROM printiag_classificacao pc WHERE pc.chave_norm = norm(v.chave)
)
ON CONFLICT (chave) DO NOTHING;

-- printiag_metas_maquinas
-- Metas de velocidade e tempo por máquina (sem dimensão de ano — metas permanentes até revisão manual).
CREATE TABLE IF NOT EXISTS printiag_metas_maquinas (
  nome_maquina                         TEXT    PRIMARY KEY,
  meta_velocidade_virando              NUMERIC,
  meta_indisponibilidade_virando_gerencial NUMERIC,
  meta_indisponibilidade_virando_area  NUMERIC,
  meta_acerto_mesma_faca               NUMERIC,
  meta_acerto_troca_faca               NUMERIC
);

INSERT INTO printiag_metas_maquinas
  (nome_maquina,
   meta_velocidade_virando,
   meta_indisponibilidade_virando_gerencial,
   meta_indisponibilidade_virando_area,
   meta_acerto_mesma_faca,
   meta_acerto_troca_faca)
VALUES
  ('Coladeira Ambition',   10087.68452, 0.1875, 0.0825, 0.08, 0.62),
  ('Coladeira Expertfold', 48122.41596, 0.1583, 0.1033, 0.09, 0.55),
  ('Coladeira Novafold',   12318.97392, 0.1508, 0.0670, 0.06, 0.76)
ON CONFLICT (nome_maquina) DO UPDATE
  SET meta_velocidade_virando              = EXCLUDED.meta_velocidade_virando,
      meta_indisponibilidade_virando_gerencial = EXCLUDED.meta_indisponibilidade_virando_gerencial,
      meta_indisponibilidade_virando_area  = EXCLUDED.meta_indisponibilidade_virando_area,
      meta_acerto_mesma_faca               = EXCLUDED.meta_acerto_mesma_faca,
      meta_acerto_troca_faca               = EXCLUDED.meta_acerto_troca_faca;

-- printiag_meta_vel_familia
-- Meta de velocidade por família virando (equipamento || tipo_virando).
-- Chave: nome_maquina concatenado diretamente com tipo_virando, sem separador.
-- Ex: 'AMBITION' + 'Braille - Cartão' = 'AMBITIONBraille - Cartão'
CREATE TABLE IF NOT EXISTS printiag_meta_vel_familia (
  familia_virando      TEXT    PRIMARY KEY,
  meta_velocidade_virando NUMERIC NOT NULL
);

INSERT INTO printiag_meta_vel_familia (familia_virando, meta_velocidade_virando) VALUES
  ('Coladeira AmbitionBraille - Cartão',              11889),
  ('Coladeira AmbitionFundo Automático - Cartão',      9856),
  ('Coladeira AmbitionFundo Automático - Micro',       3049),
  ('Coladeira AmbitionLateral - Cartão',               16296),
  ('Coladeira AmbitionNicho - Cartão',                 5238),
  ('Coladeira ExpertfoldAplicação Braille - Cartão',  33933),
  ('Coladeira ExpertfoldBraille - Cartão',             16908),
  ('Coladeira ExpertfoldFundo Automático - Cartão',   32055),
  ('Coladeira ExpertfoldLateral - Cartão',             49451),
  ('Coladeira NovafoldAplicação Braille - Cartão',   22373),
  ('Coladeira NovafoldBraille - Cartão',              13850),
  ('Coladeira NovafoldFundo Automático - Cartão',    10752),
  ('Coladeira NovafoldFundo Automático - Micro',       2998),
  ('Coladeira NovafoldLateral - Cartão',              21873),
  ('Coladeira NovafoldLateral - Micro',               2968),
  ('Coladeira NovafoldNicho - Cartão',               10011)
ON CONFLICT (familia_virando) DO UPDATE
  SET meta_velocidade_virando = EXCLUDED.meta_velocidade_virando;

-- printiag_base_micro
-- Lista de OS cujo substrato é 'Micro'. OS não cadastrada é tratada como 'Cartão' (default na MV).
CREATE TABLE IF NOT EXISTS printiag_base_micro (
  os   TEXT PRIMARY KEY,
  tipo TEXT NOT NULL CHECK (tipo IN ('Micro', 'Cartão'))
);

-- Seed — fonte: Pasta3.csv (todas as OS de substrato Micro conhecidas).
-- ON CONFLICT DO NOTHING descarta as 2 linhas duplicadas do arquivo.
INSERT INTO printiag_base_micro (os, tipo) VALUES
  ('38644', 'Micro'),
  ('38456', 'Micro'),
  ('37880', 'Micro'),
  ('37829', 'Micro'),
  ('37683', 'Micro'),
  ('37881', 'Micro'),
  ('37882', 'Micro'),
  ('38168', 'Micro'),
  ('38317', 'Micro'),
  ('37877', 'Micro'),
  ('37876', 'Micro'),
  ('37847', 'Micro'),
  ('37848', 'Micro'),
  ('38127', 'Micro'),
  ('38124', 'Micro'),
  ('38128', 'Micro'),
  ('38833', 'Micro'),
  ('37691', 'Micro'),
  ('38221', 'Micro'),
  ('38769', 'Micro'),
  ('37930', 'Micro'),
  ('38422', 'Micro'),
  ('37526', 'Micro'),
  ('37597', 'Micro'),
  ('38960', 'Micro'),
  ('39066', 'Micro'),
  ('38768', 'Micro'),
  ('39136', 'Micro'),
  ('38648', 'Micro'),
  ('38647', 'Micro'),
  ('39312', 'Micro'),
  ('38859', 'Micro'),
  ('39284', 'Micro'),
  ('39285', 'Micro'),
  ('39287', 'Micro'),
  ('39288', 'Micro'),
  ('39291', 'Micro'),
  ('39286', 'Micro'),
  ('39289', 'Micro'),
  ('39290', 'Micro'),
  ('38643', 'Micro'),
  ('38645', 'Micro'),
  ('39141', 'Micro'),
  ('39409', 'Micro'),
  ('39005', 'Micro'),
  ('39349', 'Micro'),
  ('39410', 'Micro'),
  ('39426', 'Micro'),
  ('39145', 'Micro'),
  ('39146', 'Micro'),
  ('39642', 'Micro'),
  ('38851', 'Micro'),
  ('39514', 'Micro'),
  ('39594', 'Micro'),
  ('39512', 'Micro'),
  ('38926', 'Micro'),
  ('39517', 'Micro'),
  ('39515', 'Micro'),
  ('39516', 'Micro'),
  ('39511', 'Micro'),
  ('39592', 'Micro'),
  ('37741', 'Micro')
ON CONFLICT (os) DO NOTHING;

-- printiag_acabamento_auxiliar
-- Mapeia tipo_acabamento (vindo de printag_acabamentos) → categoria de dobra.
-- O JOIN na MV usa norm() em ambos os lados, então variações de grafia/acento
-- são toleradas. Fonte: acabamento auxiliar.csv
CREATE TABLE IF NOT EXISTS printiag_acabamento_auxiliar (
  descricao  TEXT PRIMARY KEY,
  acabamento TEXT NOT NULL
);

-- Seed — 84 linhas do CSV (7 duplicadas de 'Colagem de Nicho' → ON CONFLICT DO NOTHING).
INSERT INTO printiag_acabamento_auxiliar (descricao, acabamento) VALUES
  ('Colagem Ambition',                'Fundo Automático'),
  ('Colagem Expertfold',              'Lateral'),
  ('Corte e Vinco Aut. com Braile',   'Outros'),
  ('Gravação CTP',                    'Outros'),
  ('Cortar Bobina em Folhas',         'Outros'),
  ('Corte e Vinco Automático',        'Outros'),
  ('Colagem Ambition009629',          'Fundo Automático'),
  ('Transporte',                      'Outros'),
  ('Colagem Ambition009841',          'Fundo Automático'),
  ('470x586mm 4x0 VTMAX250',          'Outros'),
  ('Transporte0100',                  'Outros'),
  ('Colagem Ambition01',              'Fundo Automático'),
  ('Colagem Manual',                  'Colagem Manual'),
  ('Braille Expertfold',              'Braille'),
  ('Colagem Fundo Automático',        'Fundo Automático'),
  ('Colagem Novafold',                'Fundo Automático'),
  ('Gravação CTP00',                  'Outros'),
  ('Colagem Ambition010122',          'Fundo Automático'),
  ('160x196mm 5x0 VTPLUS240',         'Outros'),
  ('Colagem Ambition10190',           'Fundo Automático'),
  ('Colagem',                         'Lateral'),
  ('Corte e Vinco Manual',            'Outros'),
  ('Colagem ricall',                  'Fundo Automático'),
  ('Colagem Ambition0',               'Fundo Automático'),
  ('Colagem Ambitionb',               'Fundo Automático'),
  ('Colagem Ambition''',              'Fundo Automático'),
  ('Guilhotina',                      'Outros'),
  ('Colagem Ambition010584',          'Fundo Automático'),
  ('Colagem Ambition010750',          'Fundo Automático'),
  ('Colagem Ambition010',             'Fundo Automático'),
  ('Colagem Ambition011135',          'Fundo Automático'),
  ('Colagem Rical',                   'Fundo Automático'),
  ('Colagem Ambition011',             'Fundo Automático'),
  ('Colagem Ambition011902',          'Fundo Automático'),
  ('Colagem Ambition012138012',       'Fundo Automático'),
  ('Colagem Ambition012452',          'Fundo Automático'),
  ('Colagem Expertfold0122',          'Lateral'),
  ('Colagem Ambition0123266',         'Fundo Automático'),
  ('Colagem Ambition012802',          'Fundo Automático'),
  ('178x215mm 1x0 SUPERA350',         'Outros'),
  ('Colagem Expertfold013250',        'Lateral'),
  ('300x395mm 6x0 VTPLUS240',         'Outros'),
  ('Colagem Ambition013952',          'Fundo Automático'),
  ('Colagem Berço',                   'Fundo Automático'),
  ('2º Colagem',                      'Fundo Automático'),
  ('Colagem Ambition015230',          'Fundo Automático'),
  ('Colagem Expertfold015135',        'Lateral'),
  ('Colagem Expertfold015152',        'Lateral'),
  ('Impressão',                       'Outros'),
  ('Colagem Ambition014856',          'Fundo Automático'),
  ('Colagem AF',                      'Fundo Automático'),
  ('Colagem Ambition,',               'Fundo Automático'),
  ('Expertfold',                      'Lateral'),
  ('Ambition',                        'Fundo Automático'),
  ('Colagem Expertfolds',             'Lateral'),
  ('Verniz',                          'Outros'),
  ('Montagem Gavetas',                'Colagem Manual'),
  ('Verniz UV Localizado',            'Outros'),
  ('Colagem lateral',                 'Lateral'),
  ('COLADEIRA EXPERTFOLD',            'Lateral'),
  ('Montagem de Colmeias',            'Colagem Manual'),
  ('Colagem Ambitio',                 'Fundo Automático'),
  ('502x252mm 4x0 VTMAX275',          'Outros'),
  ('Aplicação de Braille',            'Aplicação Braille'),
  ('Acabamento Manual',               'Colagem Manual'),
  ('Colagem Fundo Automatico',        'Fundo Automático'),
  ('Colagem Fundo Atuomático',        'Fundo Automático'),
  ('Colagem Fundo Automátco',         'Fundo Automático'),
  ('Alto Relevo',                     'Outros'),
  ('Colagem Hot Melting',             'Lateral'),
  ('Colagem Terceiros',               'Fundo Automático'),
  ('Aplicação Braille Expert',        'Aplicação Braille'),
  ('Colagem Expertfold - BRAILLE',    'Aplicação Braille'),
  ('Colagem Ambition - Colagem',      'Fundo Automático'),
  ('Acabamento',                      'Fundo Automático'),
  ('Corte e Vinco Aut. com Br',       'Outros'),
  ('Verniz UV Total',                 'Outros'),
  ('Braille - Expertfold',            'Aplicação Braille'),
  ('Colagem - Ambition',              'Fundo Automático'),
  ('Braile Expertfold',               'Aplicação Braille'),
  ('Colagem Ambiotion',               'Fundo Automático'),
  ('Colagem de Nicho',                'Nicho'),
  ('Hot Stamping',                    'Lateral')
ON CONFLICT (descricao) DO NOTHING;

-- =========================================================
-- DOWN (reverter):
-- DROP TABLE IF EXISTS printiag_acabamento_auxiliar;
-- DROP TABLE IF EXISTS printiag_base_micro;
-- DROP TABLE IF EXISTS printiag_meta_vel_familia;
-- DROP TABLE IF EXISTS printiag_metas_maquinas;
-- DROP TABLE IF EXISTS printag_facas;
-- DROP TABLE IF EXISTS printag_acabamentos;
-- DROP TABLE IF EXISTS printag_apontamentos;
-- DROP TABLE IF EXISTS printiag_classificacao;
-- DROP TABLE IF EXISTS printiag_maquinas;
-- DROP FUNCTION IF EXISTS norm(TEXT);
-- =========================================================

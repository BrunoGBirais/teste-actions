-- =============================================
-- PrintAG — 005: OEE Pós-Impressão
--   • Tabelas auxiliares + seed (de-para de perdas, metas, capacidade)
--   • Tabela printiag_producao_acabamento (Tipo Acabamento - MM)
--   • Views analíticas de OEE
--   • RPCs de upload snapshot (browser → Supabase)
--   • RPCs do dashboard OEE
-- =============================================

-- =======  UP  ========

-- ---------- Helpers ----------

-- Converte decimal brasileiro: '1,02' → 1.02
CREATE OR REPLACE FUNCTION parse_br_decimal(p_txt TEXT)
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_txt IS NULL OR trim(p_txt) = '' THEN RETURN NULL; END IF;
  BEGIN
    RETURN replace(trim(p_txt), ',', '.')::NUMERIC;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
END;
$$;

-- ---------- 1. Tabelas auxiliares ----------

CREATE TABLE IF NOT EXISTS aux_equipamento (
  equipamento        TEXT    PRIMARY KEY,
  area               TEXT    NOT NULL,            -- 'Corte e Vinco' | 'Acabamento'
  velocidade_limite  NUMERIC NOT NULL DEFAULT 0   -- capacidade teórica (peças/hora)
);

CREATE TABLE IF NOT EXISTS aux_classificacao_apontamento (
  tipo_apontam        TEXT NOT NULL,
  descricao           TEXT NOT NULL DEFAULT '',     -- '' = default para o tipo
  classificacao_perda TEXT NOT NULL,
  atuacao             TEXT NOT NULL,               -- Virando | Acerto | Área | Gerencial
  PRIMARY KEY (tipo_apontam, descricao)
);

CREATE TABLE IF NOT EXISTS aux_meta_equipamento (
  equipamento                TEXT    NOT NULL,
  ano                        INT     NOT NULL,
  meta_velocidade_virando    NUMERIC,              -- peças/hora
  meta_indisponibilidade_ger NUMERIC,              -- fração 0-1
  meta_oee_operacional       NUMERIC,
  meta_tempo_medio_acerto_h  NUMERIC,
  PRIMARY KEY (equipamento, ano)
);

-- ---------- 2. Seed auxiliares ----------

-- aux_equipamento
INSERT INTO aux_equipamento (equipamento, area, velocidade_limite) VALUES
  ('BOBST01',    'Corte e Vinco', 8000),
  ('BOBST02',    'Corte e Vinco', 8000),
  ('EXPERTFOLD', 'Acabamento',    48122),
  ('NOVAFOLD',   'Acabamento',    12319),
  ('AMBITION',   'Acabamento',    10088)
ON CONFLICT (equipamento) DO UPDATE
  SET area              = EXCLUDED.area,
      velocidade_limite = EXCLUDED.velocidade_limite;

-- aux_meta_equipamento (metas 2026 extraídas de junção.xlsx aba Auxiliar)
INSERT INTO aux_meta_equipamento
  (equipamento, ano, meta_velocidade_virando, meta_indisponibilidade_ger) VALUES
  ('AMBITION',   2026, 10087.68, 0.1583),
  ('EXPERTFOLD', 2026, 48122.42, 0.1508),
  ('NOVAFOLD',   2026, 12318.97, 0.1875),
  ('BOBST01',    2026, 8000,     0.15),
  ('BOBST02',    2026, 8000,     0.15)
ON CONFLICT (equipamento, ano) DO UPDATE
  SET meta_velocidade_virando    = EXCLUDED.meta_velocidade_virando,
      meta_indisponibilidade_ger = EXCLUDED.meta_indisponibilidade_ger;

-- aux_classificacao_apontamento (de-para completo de junção.xlsx aba "Auxiliar apontamento")
TRUNCATE aux_classificacao_apontamento;
INSERT INTO aux_classificacao_apontamento (tipo_apontam, descricao, classificacao_perda, atuacao) VALUES
  ('Produção',  '',                                       'Virando',               'Virando'),
  ('Acerto',    '',                                       'Acerto',                'Acerto'),
  ('Acerto',    'Preparação de Máquina',                  'Operacional Planejado', 'Área'),
  ('Acerto',    'Confecção de Canaleta',                  'Acerto',                'Acerto'),
  ('Ocioso',    '',                                       'Problema de Processo',  'Área'),
  ('Ocioso',    'Manutenção Preventiva',                  'Manutenção Preventiva', 'Gerencial'),
  ('Ocioso',    'Operador Batendo Pilha',                 'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Refeição',                               'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Ajuste de Relevo',                       'Acerto',                'Acerto'),
  ('Ocioso',    'Montagem do Destacador',                 'Acerto',                'Acerto'),
  ('Ocioso',    'Ajuste do Destacador',                   'Acerto',                'Acerto'),
  ('Ocioso',    'Troca de Serviço',                       'Acerto',                'Acerto'),
  ('Ocioso',    'Preparação de Máquina',                  'Acerto',                'Acerto'),
  ('Ocioso',    'Confecção de Canaleta',                  'Acerto',                'Acerto'),
  ('Ocioso',    'Raspando Chapa',                         'Acerto',                'Acerto'),
  ('Ocioso',    'Limpeza da Máquina',                     'Operacional Planejado', 'Área'),
  ('Ocioso',    'Colagem Manual',                         'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Aguardando Liberação CQ',                'Aguardando',            'Área'),
  ('Ocioso',    'Operadores em Outra Máquina',            'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Aguardando Impressão Off-Set',           'Aguardando',            'Área'),
  ('Ocioso',    'Falta de Serviço',                       'Sem Serviço',           'Gerencial'),
  ('Ocioso',    'Aguardando Triagem',                     'Aguardando',            'Área'),
  ('Ocioso',    'Sem Tripulação',                         'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Sem trabalho/ocioso',                    'Sem Serviço',           'Gerencial'),
  ('Ocioso',    'Máquina Quebrada',                       'Manutenção Corretiva',  'Área'),
  ('Ocioso',    'Falta de Energia',                       'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Falta de Operador',                      'Sem Serviço',           'Gerencial'),
  ('Ocioso',    'Produção Produto Piloto',                'Sem Serviço',           'Gerencial'),
  ('Ocioso',    'Manutenção Corretiva',                   'Manutenção Corretiva',  'Área'),
  ('Ocioso',    'Reunião/Palestra',                       'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Troca de Operador',                      'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Outros',                                 'Problema de Processo',  'Área'),
  ('Ocioso',    '01º Entrada Concluída',                  'Virando',               'Virando'),
  ('Ocioso',    'Teste de Material',                      'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Liberação de Máquina',                   'Acerto',                'Acerto'),
  ('Ocioso',    'Aguardando Lib. de Braille',             'Aguardando',            'Área'),
  ('Ocioso',    'Falta de Serviço Destacado',             'Aguardando',            'Área'),
  ('Ocioso',    'Aguardando Corte e Vinco',               'Aguardando',            'Área'),
  ('Ocioso',    'Eq deslocada para outra máq',            'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Limpeza do Coleiro',                     'Operacional Planejado', 'Área'),
  ('Ocioso',    'Acerto Produto Piloto',                  'Acerto',                'Acerto'),
  ('Ocioso',    'Serviços Manuais',                       'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Organização de Setor',                   'Operacional Planejado', 'Área'),
  ('Ocioso',    'Falta de Palete',                        'Aguardando',            'Área'),
  ('Ocioso',    'Aguardando Bobina',                      'Aguardando',            'Área'),
  ('Ocioso',    'Operador na Guilhotina',                 'Sem Tripulação',        'Gerencial'),
  ('Ocioso',    'Sem Pallet',                             'Aguardando',            'Área'),
  ('Ocioso',    'Troca de Faca',                          'Operacional Planejado', 'Área'),
  ('Ocioso',    'Aguardando Material',                    'Aguardando',            'Área'),
  ('Ocioso',    'Rebatendo Pilha',                        'Problema de Processo',  'Área'),
  ('Ocioso',    'Lavagem',                                'Acerto',                'Acerto'),
  ('Ocioso',    'Ajuste de Tinta',                        'Problema de Processo',  'Área'),
  ('Ocioso',    'Aguardando Aprovação',                   'Aguardando',            'Área'),
  ('Ocioso',    'Falta de Papel',                         'Aguardando',            'Área'),
  ('Ocioso',    'Aguardando Preparação de Tinta',         'Aguardando',            'Área'),
  ('Ocioso',    'Gravação de Chapa no Acerto',            'Acerto',                'Acerto'),
  ('Ocioso',    'Gravação de Chapa na Produção',          'Problema de Processo',  'Área'),
  ('Ocioso',    'Troca de Lixas',                         'Problema de Processo',  'Área'),
  ('Ocioso',    'Troca de Blanqueta',                     'Problema de Processo',  'Área'),
  ('Ocioso',    'Montagem Clichê HS',                     'Acerto',                'Acerto'),
  ('Ocioso',    'Aquecendo Máquina HS',                   'Acerto',                'Acerto'),
  ('Ocioso',    'Preparação de Fita HS',                  'Acerto',                'Acerto'),
  ('Ocioso',    'Aguardando Esfriamento da Rama',         'Acerto',                'Acerto'),
  ('Ocioso',    'Desmontando Clichê HS',                  'Acerto',                'Acerto'),
  ('Ocioso',    'Sem Apontamento',                        'Sem Apontamento',       'Gerencial');

-- ---------- 3. Tabela printiag_producao_acabamento (Tipo Acabamento - MM) ----------

CREATE TABLE IF NOT EXISTS printiag_producao_acabamento (
  id                   BIGSERIAL PRIMARY KEY,
  nro_os               TEXT        NOT NULL,
  equipamento_plan     TEXT,                    -- máquina planejada
  nome_cliente         TEXT,
  descricao_servico    TEXT,                    -- Descrição do Serviço
  tipo_acabamento      TEXT,                    -- Descrição (Colagem Ambition, etc.)
  hrs_pcp              NUMERIC(8,2),
  quantidade           INTEGER,
  atualizado_em        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_acabamento_os     ON printiag_producao_acabamento (nro_os);
CREATE INDEX IF NOT EXISTS idx_acabamento_equip  ON printiag_producao_acabamento (equipamento_plan);
CREATE INDEX IF NOT EXISTS idx_acabamento_tipo   ON printiag_producao_acabamento (tipo_acabamento);

-- ---------- 4. View classificada (join apontamentos + auxiliares) ----------

DROP VIEW IF EXISTS vw_oee_equipamento;
DROP VIEW IF EXISTS vw_apontamentos_classificado;

CREATE OR REPLACE VIEW vw_apontamentos_classificado AS
SELECT
  a.id,
  a.equipamento,
  COALESCE(e.area, 'Outros')                               AS area,
  e.velocidade_limite,
  a.inicio,
  a.fim,
  (a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE        AS dia,
  to_char(a.inicio AT TIME ZONE 'America/Sao_Paulo',
    'IYYY-"W"IW')                                          AS semana_iso,
  date_trunc('month',
    a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE       AS mes,
  EXTRACT(year FROM a.inicio AT TIME ZONE
    'America/Sao_Paulo')::INT                              AS ano,
  a.tipo_apontam,
  a.motivo,
  -- Lookup hierárquico: motivo específico primeiro, depois default do tipo
  COALESCE(cl_exact.classificacao_perda,
           cl_def.classificacao_perda,
           CASE a.tipo_apontam
             WHEN 'Produção' THEN 'Virando'
             WHEN 'Acerto'   THEN 'Acerto'
             ELSE 'Problema de Processo'
           END)                                            AS classificacao_perda,
  COALESCE(cl_exact.atuacao,
           cl_def.atuacao,
           CASE a.tipo_apontam
             WHEN 'Produção' THEN 'Virando'
             WHEN 'Acerto'   THEN 'Acerto'
             ELSE 'Área'
           END)                                            AS atuacao,
  a.duracao_min,
  a.produzido,
  a.nro_os,
  a.operador,
  a.atualizado_em
FROM apontamentos a
LEFT JOIN aux_equipamento e ON e.equipamento = a.equipamento
-- match exato por motivo
LEFT JOIN aux_classificacao_apontamento cl_exact
  ON cl_exact.tipo_apontam = a.tipo_apontam
 AND cl_exact.descricao    = a.motivo
-- fallback: default do tipo (descricao = '')
LEFT JOIN aux_classificacao_apontamento cl_def
  ON cl_def.tipo_apontam = a.tipo_apontam
 AND cl_def.descricao = '';

-- ---------- 5. View OEE agregado por equipamento × período ----------

CREATE OR REPLACE VIEW vw_oee_equipamento AS
WITH base AS (
  SELECT
    equipamento, area, velocidade_limite, dia, semana_iso, mes, ano,
    classificacao_perda, atuacao, duracao_min, produzido, tipo_apontam, motivo
  FROM vw_apontamentos_classificado
),
por_equip AS (
  SELECT
    equipamento,
    area,
    MAX(velocidade_limite)  AS velocidade_limite,
    dia, semana_iso, mes, ano,
    -- Tempo virando (produzindo)
    SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Virando')      AS min_virando,
    -- Tempo de acerto (setup)
    SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Acerto')       AS min_acerto,
    -- Improdutivos de responsabilidade da Área (ex: manutenção corretiva, aguardando CQ)
    SUM(duracao_min) FILTER (WHERE atuacao = 'Área'
                               AND classificacao_perda <> 'Virando')     AS min_improd_area,
    -- Improdutivos gerenciais (refeição, falta de serviço, etc.)
    SUM(duracao_min) FILTER (WHERE atuacao = 'Gerencial')                AS min_improd_ger,
    -- Quantidade produzida real
    SUM(produzido)   FILTER (WHERE classificacao_perda = 'Virando')      AS qtd_produzido,
    -- Contagem de blocos de acerto (para tempo médio)
    COUNT(*) FILTER (WHERE tipo_apontam = 'Acerto')                      AS qtd_acertos,
    SUM(duracao_min)                                                      AS min_total
  FROM base
  GROUP BY equipamento, area, dia, semana_iso, mes, ano
)
SELECT
  pe.*,
  -- Velocidade Média Virando (peças/hora)
  ROUND(CASE WHEN COALESCE(pe.min_virando,0) > 0
        THEN pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0)
        ELSE 0 END, 2)                                              AS vel_media_virando,
  -- Disponibilidade Operacional = Virando / (Virando + Acerto + Área-improd)
  ROUND(CASE WHEN COALESCE(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) > 0
        THEN pe.min_virando /
             NULLIF(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) * 100
        ELSE 0 END, 2)                                             AS disp_operacional,
  -- Disponibilidade Gerencial = Virando / (Virando + todos improdutivos)
  ROUND(CASE WHEN COALESCE(pe.min_total, 0) > 0
        THEN pe.min_virando / NULLIF(pe.min_total, 0) * 100
        ELSE 0 END, 2)                                             AS disp_gerencial,
  -- Desempenho = Vel. Real / Vel. Limite (%)
  ROUND(CASE WHEN COALESCE(pe.velocidade_limite, 0) > 0
             AND COALESCE(pe.min_virando, 0) > 0
        THEN (pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0))
             / pe.velocidade_limite * 100
        ELSE 0 END, 2)                                             AS desempenho,
  -- OEE Operacional = Disp_Oper × Desempenho (qualidade = 1 na v1)
  ROUND(CASE WHEN COALESCE(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) > 0
             AND COALESCE(pe.velocidade_limite, 0) > 0
             AND COALESCE(pe.min_virando, 0) > 0
        THEN (pe.min_virando /
              NULLIF(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0))
             * ((pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0))
                / pe.velocidade_limite)
             * 100
        ELSE 0 END, 2)                                             AS oee_operacional,
  -- Tempo médio de acerto (horas)
  ROUND(CASE WHEN COALESCE(pe.qtd_acertos, 0) > 0
        THEN (pe.min_acerto / pe.qtd_acertos) / 60.0
        ELSE 0 END, 3)                                             AS tempo_medio_acerto_h,
  -- Índice de improdutivos (%)
  ROUND(CASE WHEN COALESCE(pe.min_total, 0) > 0
        THEN (pe.min_total - COALESCE(pe.min_virando, 0)) / pe.min_total * 100
        ELSE 0 END, 2)                                             AS indice_improdutivos,
  m.meta_tempo_medio_acerto_h
FROM por_equip pe
LEFT JOIN aux_meta_equipamento m ON m.equipamento = pe.equipamento AND m.ano = pe.ano;

-- ---------- 6. RPCs de Upload Snapshot ----------

-- 6.1  Inicia snapshot: apaga dados de produção (mantém auxiliares)
CREATE OR REPLACE FUNCTION printag_snapshot_begin()
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  -- TRUNCATE evita o bloqueio "DELETE requires a WHERE clause" e é mais rápido.
  -- CASCADE resolve as FKs (facas/apontamentos → ordens_servico).
  TRUNCATE apontamentos, facas, printiag_producao_acabamento, ordens_servico
    RESTART IDENTITY CASCADE;
END;
$$;

-- 6.2  Upload de Apontamentos (lote)
--      p_rows: array JSON com objetos:
--        { equipamento, inicio, fim, tipo_apontam, tempo_h,
--          motivo, nro_os, produzido, titulo, nome_cliente, operador }
CREATE OR REPLACE FUNCTION printag_snapshot_apontamentos(p_rows JSONB)
RETURNS INT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE v_n INT;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  -- Garante OS referenciados existam (upsert mínimo, deduplicado por nro_os)
  INSERT INTO ordens_servico (nro_os, titulo, nome_cliente, atualizado_em)
  SELECT DISTINCT ON (s.os) s.os, s.tit, s.cli, NOW()
  FROM (
    SELECT
      NULLIF(trim(r->>'nro_os'), '')       AS os,
      NULLIF(trim(r->>'titulo'), '')       AS tit,
      NULLIF(trim(r->>'nome_cliente'), '') AS cli
    FROM jsonb_array_elements(p_rows) r
  ) s
  WHERE s.os IS NOT NULL
  ORDER BY s.os
  ON CONFLICT (nro_os) DO UPDATE
    SET titulo       = COALESCE(EXCLUDED.titulo, ordens_servico.titulo),
        nome_cliente = COALESCE(EXCLUDED.nome_cliente, ordens_servico.nome_cliente),
        atualizado_em = NOW();

  -- Insere apontamentos
  INSERT INTO apontamentos
    (equipamento, inicio, fim, tipo_apontam, tempo_total,
     motivo, nro_os, produzido, operador, atualizado_em)
  SELECT
    trim(r->>'equipamento'),
    parse_br_datetime(r->>'inicio'),
    parse_br_datetime(r->>'fim'),
    trim(r->>'tipo_apontam'),
    -- tempo_h vem em horas decimais; converte para INTERVAL
    CASE WHEN (r->>'tempo_h') IS NOT NULL AND (r->>'tempo_h') != ''
         THEN ((r->>'tempo_h')::NUMERIC * 3600 || ' seconds')::INTERVAL
         ELSE NULL END,
    NULLIF(trim(r->>'motivo'), ''),
    NULLIF(trim(r->>'nro_os'), ''),
    COALESCE((r->>'produzido')::INTEGER, 0),
    NULLIF(trim(r->>'operador'), ''),
    NOW()
  FROM jsonb_array_elements(p_rows) r
  WHERE NULLIF(trim(r->>'equipamento'), '') IS NOT NULL
    AND parse_br_datetime(r->>'inicio') IS NOT NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- 6.3  Upload de Acabamento (Tipo Acabamento - MM)
--      p_rows: [ { nro_os, equipamento_plan, nome_cliente,
--                  descricao_servico, tipo_acabamento, hrs_pcp, quantidade } ]
CREATE OR REPLACE FUNCTION printag_snapshot_acabamento(p_rows JSONB)
RETURNS INT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE v_n INT;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  -- Cria/atualiza OS a partir dos dados de acabamento
  INSERT INTO ordens_servico (nro_os, titulo, nome_cliente, quantidade, tipo_servico, setor, atualizado_em)
  SELECT DISTINCT ON (NULLIF(trim(r->>'nro_os'), ''))
    NULLIF(trim(r->>'nro_os'), ''),
    NULLIF(trim(r->>'descricao_servico'), ''),
    NULLIF(trim(r->>'nome_cliente'), ''),
    CASE WHEN (r->>'quantidade') IS NOT NULL AND (r->>'quantidade') != ''
         THEN (r->>'quantidade')::INTEGER ELSE NULL END,
    NULLIF(trim(r->>'tipo_acabamento'), ''),
    'Acabamento',
    NOW()
  FROM jsonb_array_elements(p_rows) r
  WHERE NULLIF(trim(r->>'nro_os'), '') IS NOT NULL
  ON CONFLICT (nro_os) DO UPDATE
    SET titulo       = COALESCE(EXCLUDED.titulo, ordens_servico.titulo),
        nome_cliente = COALESCE(EXCLUDED.nome_cliente, ordens_servico.nome_cliente),
        quantidade   = COALESCE(EXCLUDED.quantidade, ordens_servico.quantidade),
        tipo_servico = COALESCE(EXCLUDED.tipo_servico, ordens_servico.tipo_servico),
        setor        = COALESCE(EXCLUDED.setor, ordens_servico.setor),
        atualizado_em = NOW();

  INSERT INTO printiag_producao_acabamento
    (nro_os, equipamento_plan, nome_cliente, descricao_servico,
     tipo_acabamento, hrs_pcp, quantidade, atualizado_em)
  SELECT
    NULLIF(trim(r->>'nro_os'), ''),
    NULLIF(trim(r->>'equipamento_plan'), ''),
    NULLIF(trim(r->>'nome_cliente'), ''),
    NULLIF(trim(r->>'descricao_servico'), ''),
    NULLIF(trim(r->>'tipo_acabamento'), ''),
    CASE WHEN (r->>'hrs_pcp') IS NOT NULL AND (r->>'hrs_pcp') != ''
         THEN (r->>'hrs_pcp')::NUMERIC ELSE NULL END,
    CASE WHEN (r->>'quantidade') IS NOT NULL AND (r->>'quantidade') != ''
         THEN (r->>'quantidade')::INTEGER ELSE NULL END,
    NOW()
  FROM jsonb_array_elements(p_rows) r
  WHERE NULLIF(trim(r->>'nro_os'), '') IS NOT NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- 6.4  Upload de Metros Lineares / Facas
--      p_rows: [ { nro_os, faca, lado_1, lado_2, montagem,
--                  l1_substrato, l2_substrato, l1_corte, l2_corte } ]
CREATE OR REPLACE FUNCTION printag_snapshot_facas(p_rows JSONB)
RETURNS INT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE v_n INT;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  -- Garante OS mínima
  INSERT INTO ordens_servico (nro_os, atualizado_em)
  SELECT DISTINCT NULLIF(trim(r->>'nro_os'), ''), NOW()
  FROM jsonb_array_elements(p_rows) r
  WHERE NULLIF(trim(r->>'nro_os'), '') IS NOT NULL
  ON CONFLICT (nro_os) DO NOTHING;

  INSERT INTO facas
    (nro_os, faca, lado_1, lado_2, montagem,
     l1_substrato, l2_substrato, l1_corte, l2_corte, atualizado_em)
  SELECT DISTINCT ON (s.nro_os)
    s.nro_os, s.faca, s.lado_1, s.lado_2, s.montagem,
    s.l1_substrato, s.l2_substrato, s.l1_corte, s.l2_corte, NOW()
  FROM (
    SELECT
      NULLIF(trim(r->>'nro_os'), '') AS nro_os,
      NULLIF(trim(r->>'faca'), '')   AS faca,
      CASE WHEN (r->>'lado_1') IS NOT NULL AND (r->>'lado_1') != ''
           THEN (r->>'lado_1')::NUMERIC ELSE NULL END AS lado_1,
      CASE WHEN (r->>'lado_2') IS NOT NULL AND (r->>'lado_2') != ''
           THEN (r->>'lado_2')::NUMERIC ELSE NULL END AS lado_2,
      CASE WHEN (r->>'montagem') IS NOT NULL AND (r->>'montagem') != ''
           THEN (r->>'montagem')::INTEGER ELSE NULL END AS montagem,
      CASE WHEN (r->>'l1_substrato') IS NOT NULL AND (r->>'l1_substrato') != ''
           THEN (r->>'l1_substrato')::NUMERIC ELSE NULL END AS l1_substrato,
      CASE WHEN (r->>'l2_substrato') IS NOT NULL AND (r->>'l2_substrato') != ''
           THEN (r->>'l2_substrato')::NUMERIC ELSE NULL END AS l2_substrato,
      CASE WHEN (r->>'l1_corte') IS NOT NULL AND (r->>'l1_corte') != ''
           THEN (r->>'l1_corte')::NUMERIC ELSE NULL END AS l1_corte,
      CASE WHEN (r->>'l2_corte') IS NOT NULL AND (r->>'l2_corte') != ''
           THEN (r->>'l2_corte')::NUMERIC ELSE NULL END AS l2_corte
    FROM jsonb_array_elements(p_rows) r
  ) s
  WHERE s.nro_os IS NOT NULL
  ORDER BY s.nro_os
  ON CONFLICT (nro_os) DO UPDATE
    SET faca         = EXCLUDED.faca,
        lado_1       = EXCLUDED.lado_1,
        lado_2       = EXCLUDED.lado_2,
        montagem     = EXCLUDED.montagem,
        l1_substrato = EXCLUDED.l1_substrato,
        l2_substrato = EXCLUDED.l2_substrato,
        l1_corte     = EXCLUDED.l1_corte,
        l2_corte     = EXCLUDED.l2_corte,
        atualizado_em = NOW();

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- ---------- 7. RPCs do Dashboard OEE ----------

-- 7.1  KPIs globais OEE
CREATE OR REPLACE FUNCTION printag_oee_kpis(p_dias INT DEFAULT 30)
RETURNS JSON
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_since TIMESTAMPTZ;
  v JSON;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_since := CURRENT_TIMESTAMP - (GREATEST(p_dias,1) || ' days')::INTERVAL;

  WITH ap AS (
    SELECT
      classificacao_perda, atuacao, duracao_min, produzido, tipo_apontam, velocidade_limite
    FROM vw_apontamentos_classificado
    WHERE inicio >= v_since
  ),
  agg AS (
    SELECT
      COALESCE(SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Virando'), 0)          AS min_virando,
      COALESCE(SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Acerto'),   0)          AS min_acerto,
      COALESCE(SUM(duracao_min) FILTER (WHERE atuacao = 'Área'
                                          AND classificacao_perda <> 'Virando'), 0)          AS min_improd_area,
      COALESCE(SUM(duracao_min) FILTER (WHERE atuacao = 'Gerencial'),            0)          AS min_improd_ger,
      COALESCE(SUM(produzido)   FILTER (WHERE classificacao_perda = 'Virando'),  0)::BIGINT  AS qtd_produzido,
      COUNT(*)                 FILTER (WHERE tipo_apontam = 'Acerto')                       AS qtd_acertos,
      COALESCE(SUM(duracao_min), 0)                                                          AS min_total,
      -- velocidade limite ponderada pelo tempo virando de cada máquina
      SUM(duracao_min * COALESCE(velocidade_limite,0)) FILTER (WHERE classificacao_perda='Virando')
        / NULLIF(SUM(duracao_min) FILTER (WHERE classificacao_perda='Virando'), 0)           AS vel_limite_ponderada
    FROM ap
  )
  SELECT json_build_object(
    'disp_operacional',
      ROUND(agg.min_virando /
        NULLIF(agg.min_virando + agg.min_acerto + agg.min_improd_area, 0) * 100, 2),
    'desempenho',
      ROUND(CASE WHEN COALESCE(agg.vel_limite_ponderada,0) > 0
                  AND agg.min_virando > 0
            THEN (agg.qtd_produzido::NUMERIC / (agg.min_virando/60.0))
                 / agg.vel_limite_ponderada * 100
            ELSE 0 END, 2),
    'oee_operacional',
      ROUND(
        (agg.min_virando / NULLIF(agg.min_virando + agg.min_acerto + agg.min_improd_area, 0))
        * CASE WHEN COALESCE(agg.vel_limite_ponderada,0)>0 AND agg.min_virando>0
               THEN (agg.qtd_produzido::NUMERIC/(agg.min_virando/60.0))/agg.vel_limite_ponderada
               ELSE 0 END
        * 100
      , 2),
    'vel_media_virando',
      ROUND(CASE WHEN agg.min_virando > 0
            THEN agg.qtd_produzido::NUMERIC / (agg.min_virando / 60.0)
            ELSE 0 END, 0),
    'tempo_medio_acerto_h',
      ROUND(CASE WHEN agg.qtd_acertos > 0
            THEN (agg.min_acerto / agg.qtd_acertos) / 60.0
            ELSE 0 END, 2),
    'indice_improdutivos',
      ROUND(CASE WHEN agg.min_total > 0
            THEN (agg.min_total - agg.min_virando) / agg.min_total * 100
            ELSE 0 END, 2),
    'min_virando',    ROUND(agg.min_virando::NUMERIC, 0),
    'min_acerto',     ROUND(agg.min_acerto::NUMERIC, 0),
    'qtd_produzido',  agg.qtd_produzido,
    'p_dias',         p_dias
  ) INTO v FROM agg;

  RETURN v;
END;
$$;

-- 7.2  OEE por equipamento (para o período)
CREATE OR REPLACE FUNCTION printag_oee_por_equipamento(p_dias INT DEFAULT 30)
RETURNS TABLE(
  equipamento          TEXT,
  area                 TEXT,
  velocidade_limite    NUMERIC,
  meta_velocidade      NUMERIC,
  min_virando          NUMERIC,
  min_acerto           NUMERIC,
  min_improd_area      NUMERIC,
  min_improd_ger       NUMERIC,
  qtd_produzido        BIGINT,
  qtd_acertos          BIGINT,
  vel_media_virando    NUMERIC,
  disp_operacional     NUMERIC,
  desempenho           NUMERIC,
  oee_operacional      NUMERIC,
  tempo_medio_acerto_h NUMERIC,
  indice_improdutivos  NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_since := CURRENT_TIMESTAMP - (GREATEST(p_dias,1) || ' days')::INTERVAL;

  RETURN QUERY
  WITH ap AS (
    SELECT
      v.equipamento, v.area, v.velocidade_limite,
      v.classificacao_perda, v.atuacao, v.duracao_min, v.produzido, v.tipo_apontam
    FROM vw_apontamentos_classificado v
    WHERE v.inicio >= v_since
  ),
  agg AS (
    SELECT
      a.equipamento,
      MAX(a.area)               AS area,
      MAX(a.velocidade_limite)  AS vel_lim,
      COALESCE(SUM(a.duracao_min) FILTER (WHERE a.classificacao_perda='Virando'),0)      AS mv,
      COALESCE(SUM(a.duracao_min) FILTER (WHERE a.classificacao_perda='Acerto'),0)       AS ma,
      COALESCE(SUM(a.duracao_min) FILTER (WHERE a.atuacao='Área'
                                           AND a.classificacao_perda<>'Virando'),0)      AS mia,
      COALESCE(SUM(a.duracao_min) FILTER (WHERE a.atuacao='Gerencial'),0)                AS mig,
      COALESCE(SUM(a.produzido)   FILTER (WHERE a.classificacao_perda='Virando'),0)::BIGINT AS qp,
      COUNT(*)                  FILTER (WHERE a.tipo_apontam='Acerto')                  AS qa,
      COALESCE(SUM(a.duracao_min),0)                                                     AS mt
    FROM ap a
    GROUP BY a.equipamento
  )
  SELECT
    g.equipamento,
    g.area,
    g.vel_lim,
    m.meta_velocidade_virando,
    ROUND(g.mv::NUMERIC, 2),
    ROUND(g.ma::NUMERIC, 2),
    ROUND(g.mia::NUMERIC, 2),
    ROUND(g.mig::NUMERIC, 2),
    g.qp,
    g.qa,
    -- vel media
    ROUND(CASE WHEN g.mv>0 THEN g.qp::NUMERIC/(g.mv/60.0) ELSE 0 END, 0),
    -- disp operacional
    ROUND(g.mv/NULLIF(g.mv+g.ma+g.mia,0)*100, 2),
    -- desempenho
    ROUND(CASE WHEN COALESCE(g.vel_lim,0)>0 AND g.mv>0
          THEN (g.qp::NUMERIC/(g.mv/60.0))/g.vel_lim*100 ELSE 0 END, 2),
    -- oee
    ROUND(
      (g.mv/NULLIF(g.mv+g.ma+g.mia,0)) *
      CASE WHEN COALESCE(g.vel_lim,0)>0 AND g.mv>0
           THEN (g.qp::NUMERIC/(g.mv/60.0))/g.vel_lim ELSE 0 END
      * 100, 2),
    -- tempo medio acerto h
    ROUND(CASE WHEN g.qa>0 THEN (g.ma/g.qa)/60.0 ELSE 0 END, 2),
    -- indice improdutivos
    ROUND(CASE WHEN g.mt>0 THEN (g.mt-g.mv)/g.mt*100 ELSE 0 END, 2)
  FROM agg g
  LEFT JOIN aux_meta_equipamento m
    ON m.equipamento = g.equipamento
   AND m.ano = EXTRACT(year FROM NOW())::INT
  ORDER BY g.area, g.equipamento;
END;
$$;

-- 7.3  Pareto de improdutivos
CREATE OR REPLACE FUNCTION printag_oee_pareto_improdutivos(
  p_dias   INT  DEFAULT 30,
  p_top    INT  DEFAULT 12
)
RETURNS TABLE(
  classificacao_perda TEXT,
  atuacao             TEXT,
  qtd_ocorrencias     BIGINT,
  horas_parado        NUMERIC,
  pct_do_total        NUMERIC,
  pct_acumulado       NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_since := CURRENT_TIMESTAMP - (GREATEST(p_dias,1) || ' days')::INTERVAL;

  RETURN QUERY
  WITH imp AS (
    SELECT
      v.classificacao_perda,
      v.atuacao,
      COUNT(*)::BIGINT                                  AS qtd,
      ROUND(SUM(v.duracao_min)/60.0::NUMERIC, 2)        AS hrs
    FROM vw_apontamentos_classificado v
    WHERE v.inicio >= v_since
      AND v.classificacao_perda <> 'Virando'
    GROUP BY v.classificacao_perda, v.atuacao
    ORDER BY hrs DESC
    LIMIT GREATEST(p_top, 1)
  ),
  total AS (SELECT SUM(hrs) AS tot FROM imp)
  SELECT
    i.classificacao_perda,
    i.atuacao,
    i.qtd,
    i.hrs,
    ROUND(i.hrs / NULLIF(t.tot,0) * 100, 2),
    ROUND(SUM(i.hrs) OVER (ORDER BY i.hrs DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(t.tot,0) * 100, 2)
  FROM imp i, total t;
END;
$$;

-- 7.4  Velocidade média virando por semana (tendência)
CREATE OR REPLACE FUNCTION printag_oee_velocidade_semanal(p_semanas INT DEFAULT 12)
RETURNS TABLE(
  semana_iso        TEXT,
  equipamento       TEXT,
  vel_media_virando NUMERIC,
  meta_velocidade   NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_since := CURRENT_TIMESTAMP - (GREATEST(p_semanas,1) * 7 || ' days')::INTERVAL;

  RETURN QUERY
  WITH ap AS (
    SELECT v.equipamento, v.semana_iso, v.duracao_min, v.produzido, v.classificacao_perda
    FROM vw_apontamentos_classificado v
    WHERE v.inicio >= v_since
  ),
  agg AS (
    SELECT
      a.semana_iso, a.equipamento,
      SUM(a.duracao_min) FILTER (WHERE a.classificacao_perda='Virando')     AS mv,
      SUM(a.produzido)   FILTER (WHERE a.classificacao_perda='Virando')::BIGINT AS qp
    FROM ap a
    GROUP BY a.semana_iso, a.equipamento
  )
  SELECT
    g.semana_iso,
    g.equipamento,
    ROUND(CASE WHEN COALESCE(g.mv,0)>0 THEN g.qp::NUMERIC/(g.mv/60.0) ELSE 0 END, 0),
    m.meta_velocidade_virando
  FROM agg g
  LEFT JOIN aux_meta_equipamento m
    ON m.equipamento = g.equipamento
   AND m.ano = EXTRACT(year FROM NOW())::INT
  ORDER BY g.semana_iso, g.equipamento;
END;
$$;

-- 7.5  Produção por tipo de acabamento (semanal)
CREATE OR REPLACE FUNCTION printag_oee_producao_por_tipo(p_dias INT DEFAULT 30)
RETURNS TABLE(
  tipo_acabamento  TEXT,
  equipamento_plan TEXT,
  qtd_os           BIGINT,
  qtd_produzida    BIGINT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  v_since := CURRENT_TIMESTAMP - (GREATEST(p_dias,1) || ' days')::INTERVAL;

  RETURN QUERY
  SELECT
    COALESCE(pa.tipo_acabamento, 'Sem tipo')::TEXT,
    COALESCE(pa.equipamento_plan, 'Outros')::TEXT,
    COUNT(DISTINCT pa.nro_os)::BIGINT                                AS qtd_os,
    COALESCE(SUM(a.produzido),0)::BIGINT                             AS qtd_produzida
  FROM printiag_producao_acabamento pa
  LEFT JOIN apontamentos a ON a.nro_os = pa.nro_os AND a.inicio >= v_since
  GROUP BY pa.tipo_acabamento, pa.equipamento_plan
  ORDER BY qtd_produzida DESC;
END;
$$;

-- ---------- 8. GRANTs ----------
GRANT EXECUTE ON FUNCTION parse_br_decimal(TEXT)                    TO authenticated;
GRANT EXECUTE ON FUNCTION printag_snapshot_begin()                   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_snapshot_apontamentos(JSONB)       TO authenticated;
GRANT EXECUTE ON FUNCTION printag_snapshot_acabamento(JSONB)         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_snapshot_facas(JSONB)              TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_kpis(INT)                      TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_por_equipamento(INT)           TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_pareto_improdutivos(INT,INT)   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_velocidade_semanal(INT)        TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_producao_por_tipo(INT)         TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- REVOKE EXECUTE ON FUNCTION printag_oee_producao_por_tipo(INT)         FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_oee_velocidade_semanal(INT)         FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_oee_pareto_improdutivos(INT,INT)    FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_oee_por_equipamento(INT)            FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_oee_kpis(INT)                       FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_snapshot_facas(JSONB)               FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_snapshot_acabamento(JSONB)          FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_snapshot_apontamentos(JSONB)        FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_snapshot_begin()                    FROM authenticated;
-- DROP FUNCTION IF EXISTS printag_oee_producao_por_tipo(INT);
-- DROP FUNCTION IF EXISTS printag_oee_velocidade_semanal(INT);
-- DROP FUNCTION IF EXISTS printag_oee_pareto_improdutivos(INT,INT);
-- DROP FUNCTION IF EXISTS printag_oee_por_equipamento(INT);
-- DROP FUNCTION IF EXISTS printag_oee_kpis(INT);
-- DROP FUNCTION IF EXISTS printag_snapshot_facas(JSONB);
-- DROP FUNCTION IF EXISTS printag_snapshot_acabamento(JSONB);
-- DROP FUNCTION IF EXISTS printag_snapshot_apontamentos(JSONB);
-- DROP FUNCTION IF EXISTS printag_snapshot_begin();
-- DROP VIEW IF EXISTS vw_oee_equipamento;
-- DROP VIEW IF EXISTS vw_apontamentos_classificado;
-- DROP TABLE IF EXISTS printiag_producao_acabamento;
-- DROP TABLE IF EXISTS aux_meta_equipamento;
-- DROP TABLE IF EXISTS aux_classificacao_apontamento;
-- DROP TABLE IF EXISTS aux_equipamento;
-- DROP FUNCTION IF EXISTS parse_br_decimal(TEXT);
-- NOTIFY pgrst, 'reload schema';

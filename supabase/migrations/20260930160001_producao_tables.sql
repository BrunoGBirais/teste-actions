-- =============================================
-- PrintAG — 001: Tabelas de Produção + Views analíticas
-- Schema determinístico para o agente IA consultar via SQL.
-- As planilhas do Google Drive são sincronizadas para cá pelo n8n
-- (workflow printag-upload-dataset).
-- =============================================

-- =======  UP  ========

-- ---------- Helpers ----------

-- Converte string "DD/MM/AAAA-HH:MM" (formato dos apontamentos) em timestamptz.
-- Retorna NULL para vazio/formato inesperado, em vez de quebrar o ETL.
CREATE OR REPLACE FUNCTION parse_br_datetime(p_txt TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_clean TEXT;
BEGIN
  IF p_txt IS NULL THEN RETURN NULL; END IF;
  v_clean := trim(p_txt);
  IF v_clean = '' THEN RETURN NULL; END IF;
  v_clean := replace(v_clean, '-', ' ');
  BEGIN
    RETURN to_timestamp(v_clean, 'DD/MM/YYYY HH24:MI')
           AT TIME ZONE 'America/Sao_Paulo';
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
END;
$$;

-- ---------- Tabelas ----------

-- 1) ORDENS DE SERVIÇO
CREATE TABLE IF NOT EXISTS ordens_servico (
  nro_os          TEXT        PRIMARY KEY,
  titulo          TEXT,
  nome_cliente    TEXT,
  quantidade      INTEGER,
  tipo_servico    TEXT,
  setor           TEXT,
  tipo_orcamento  TEXT,
  repetido        TEXT,
  repetiu_erro    BOOLEAN,
  atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_os_setor        ON ordens_servico (setor);
CREATE INDEX IF NOT EXISTS idx_os_cliente      ON ordens_servico (nome_cliente);
CREATE INDEX IF NOT EXISTS idx_os_repetiu_erro ON ordens_servico (repetiu_erro) WHERE repetiu_erro = TRUE;

-- 2) FACAS (ferramental por OS)
CREATE TABLE IF NOT EXISTS facas (
  nro_os         TEXT PRIMARY KEY REFERENCES ordens_servico(nro_os) ON DELETE CASCADE,
  faca           TEXT,
  lado_1         NUMERIC(10,2),
  lado_2         NUMERIC(10,2),
  montagem       INTEGER,
  l1_substrato   NUMERIC(10,2),
  l2_substrato   NUMERIC(10,2),
  l1_corte       NUMERIC(10,2),
  l2_corte       NUMERIC(10,2),
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3) APONTAMENTOS (diário de bordo do chão de fábrica)
CREATE TABLE IF NOT EXISTS apontamentos (
  id             BIGSERIAL PRIMARY KEY,
  equipamento    TEXT        NOT NULL,
  inicio         TIMESTAMPTZ NOT NULL,
  fim            TIMESTAMPTZ,
  tipo_apontam   TEXT        NOT NULL,
  tempo_total    INTERVAL,
  motivo         TEXT,
  nro_os         TEXT        REFERENCES ordens_servico(nro_os) ON DELETE SET NULL,
  produzido      INTEGER     NOT NULL DEFAULT 0,
  operador       TEXT,
  atualizado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_inicio_fim CHECK (fim IS NULL OR fim >= inicio)
);

CREATE INDEX IF NOT EXISTS idx_apont_os          ON apontamentos (nro_os);
CREATE INDEX IF NOT EXISTS idx_apont_equip       ON apontamentos (equipamento);
CREATE INDEX IF NOT EXISTS idx_apont_inicio      ON apontamentos (inicio DESC);
CREATE INDEX IF NOT EXISTS idx_apont_tipo        ON apontamentos (tipo_apontam);
CREATE INDEX IF NOT EXISTS idx_apont_equip_tipo  ON apontamentos (equipamento, tipo_apontam);
CREATE INDEX IF NOT EXISTS idx_apont_motivo      ON apontamentos (motivo) WHERE motivo IS NOT NULL;

-- Coluna gerada: duração efetiva em minutos.
ALTER TABLE apontamentos
  ADD COLUMN IF NOT EXISTS duracao_min NUMERIC
  GENERATED ALWAYS AS (
    COALESCE(
      EXTRACT(EPOCH FROM tempo_total) / 60.0,
      EXTRACT(EPOCH FROM (fim - inicio)) / 60.0
    )
  ) STORED;

-- ---------- Views analíticas ----------

CREATE OR REPLACE VIEW vw_status_os AS
SELECT
  os.nro_os,
  os.titulo,
  os.nome_cliente,
  os.setor,
  os.tipo_servico,
  os.quantidade,
  os.repetiu_erro,
  COALESCE(SUM(a.produzido), 0)                                                  AS produzido_total,
  CASE
    WHEN os.quantidade IS NULL OR os.quantidade = 0 THEN NULL
    ELSE ROUND( (COALESCE(SUM(a.produzido),0)::NUMERIC / os.quantidade) * 100, 2)
  END                                                                            AS pct_concluido,
  COALESCE(SUM(a.duracao_min) FILTER (WHERE a.tipo_apontam = 'Produção'), 0)     AS minutos_producao,
  COALESCE(SUM(a.duracao_min) FILTER (WHERE a.tipo_apontam = 'Ocioso'),   0)     AS minutos_ocioso,
  MIN(a.inicio)                                                                  AS primeiro_apontamento,
  MAX(COALESCE(a.fim, a.inicio))                                                 AS ultimo_apontamento,
  COUNT(DISTINCT a.equipamento)                                                  AS qtd_equipamentos
FROM ordens_servico os
LEFT JOIN apontamentos a ON a.nro_os = os.nro_os
GROUP BY os.nro_os;

CREATE OR REPLACE VIEW vw_tempo_parada_maquina AS
SELECT
  equipamento,
  COALESCE(motivo, 'Não informado')             AS motivo,
  COUNT(*)                                      AS qtd_paradas,
  ROUND(SUM(duracao_min)::NUMERIC, 2)           AS minutos_parado,
  ROUND((SUM(duracao_min)/60.0)::NUMERIC, 2)    AS horas_parado,
  MIN(inicio)                                   AS desde,
  MAX(COALESCE(fim, inicio))                    AS ate
FROM apontamentos
WHERE tipo_apontam = 'Ocioso'
GROUP BY equipamento, COALESCE(motivo, 'Não informado');

CREATE OR REPLACE VIEW vw_producao_diaria AS
SELECT
  equipamento,
  (inicio AT TIME ZONE 'America/Sao_Paulo')::DATE      AS dia,
  SUM(produzido)                                       AS produzido,
  ROUND(SUM(duracao_min) FILTER (WHERE tipo_apontam = 'Produção')::NUMERIC, 2) AS minutos_producao,
  ROUND(SUM(duracao_min) FILTER (WHERE tipo_apontam = 'Ocioso')::NUMERIC,   2) AS minutos_ocioso
FROM apontamentos
GROUP BY equipamento, (inicio AT TIME ZONE 'America/Sao_Paulo')::DATE;

CREATE OR REPLACE VIEW vw_refugo_por_setor AS
SELECT
  setor,
  COUNT(*)                                                  AS total_os,
  COUNT(*) FILTER (WHERE repetiu_erro)                      AS os_com_refugo,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE repetiu_erro) / NULLIF(COUNT(*),0),
    2
  )                                                         AS pct_refugo
FROM ordens_servico
GROUP BY setor;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP VIEW IF EXISTS vw_refugo_por_setor;
-- DROP VIEW IF EXISTS vw_producao_diaria;
-- DROP VIEW IF EXISTS vw_tempo_parada_maquina;
-- DROP VIEW IF EXISTS vw_status_os;
-- DROP TABLE IF EXISTS apontamentos;
-- DROP TABLE IF EXISTS facas;
-- DROP TABLE IF EXISTS ordens_servico;
-- DROP FUNCTION IF EXISTS parse_br_datetime(TEXT);
-- NOTIFY pgrst, 'reload schema';

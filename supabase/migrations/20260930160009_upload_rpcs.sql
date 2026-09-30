-- =========================================================
-- PrintAG — 009: Upload RPCs v2
-- Substitui printag_snapshot_* com versões _v2 que usam
-- as novas tabelas printag_apontamentos / acabamentos / facas.
-- =========================================================

-- =========================================================
-- 1. printag_snapshot_begin_v2
-- Limpa as 3 tabelas espelho antes de um novo upload.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_snapshot_begin_v2()
  RETURNS VOID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
BEGIN
  TRUNCATE TABLE printag_apontamentos  RESTART IDENTITY CASCADE;
  TRUNCATE TABLE printag_acabamentos   RESTART IDENTITY CASCADE;
  TRUNCATE TABLE printag_facas         RESTART IDENTITY CASCADE;
END;
$$;

-- =========================================================
-- 2. printag_snapshot_apontamentos_v2
-- INSERT em lote em printag_apontamentos (sem lookup de IDs).
-- p_rows: array JSONB com campos do CSV já normalizados pelo Python.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_snapshot_apontamentos_v2(p_rows JSONB)
  RETURNS INT
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO printag_apontamentos
    (equipamento, tipo_apontam, motivo,
     inicio, fim,
     nro_os, produzido,
     titulo_produto, nome_cliente, operador)
  SELECT
    r.equipamento,
    r.tipo_apontam,
    NULLIF(trim(r.motivo),   ''),
    TO_TIMESTAMP(r.inicio,            'DD/MM/YYYY-HH24:MI'),
    TO_TIMESTAMP(NULLIF(trim(r.fim), ''), 'DD/MM/YYYY-HH24:MI'),
    NULLIF(REGEXP_REPLACE(COALESCE(trim(r.nro_os), ''), '^0+', ''), ''),
    COALESCE(r.produzido::INT, 0),
    NULLIF(trim(r.titulo_produto), ''),
    NULLIF(trim(r.nome_cliente),   ''),
    NULLIF(trim(r.operador),       '')
  FROM jsonb_to_recordset(p_rows) AS r(
    equipamento    TEXT,
    tipo_apontam   TEXT,
    motivo         TEXT,
    inicio         TEXT,
    fim            TEXT,
    nro_os         TEXT,
    produzido      TEXT,
    titulo_produto TEXT,
    nome_cliente   TEXT,
    operador       TEXT
  )
  WHERE r.equipamento IS NOT NULL
    AND r.tipo_apontam IS NOT NULL
    AND r.inicio       IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =========================================================
-- 3. printag_snapshot_acabamentos_v2
-- INSERT em lote em printag_acabamentos.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_snapshot_acabamentos_v2(p_rows JSONB)
  RETURNS INT
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO printag_acabamentos
    (nro_os, equipamento_plan, nome_cliente, descricao_servico,
     tipo_acabamento, hrs_pcp, quantidade, ini_calculado, fim_calculado)
  SELECT
    NULLIF(REGEXP_REPLACE(COALESCE(trim(r.nro_os), ''), '^0+', ''), ''),
    NULLIF(trim(r.equipamento_plan),  ''),
    NULLIF(trim(r.nome_cliente),      ''),
    NULLIF(trim(r.descricao_servico), ''),
    NULLIF(trim(r.tipo_acabamento),   ''),
    NULLIF(r.hrs_pcp,   '')::NUMERIC,
    NULLIF(r.quantidade,'')::INT,
    NULLIF(r.ini_calculado,'')::DATE,
    NULLIF(r.fim_calculado,'')::DATE
  FROM jsonb_to_recordset(p_rows) AS r(
    nro_os            TEXT,
    equipamento_plan  TEXT,
    nome_cliente      TEXT,
    descricao_servico TEXT,
    tipo_acabamento   TEXT,
    hrs_pcp           TEXT,
    quantidade        TEXT,
    ini_calculado     TEXT,
    fim_calculado     TEXT
  )
  WHERE r.nro_os IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =========================================================
-- 4. printag_snapshot_facas_v2
-- INSERT em lote em printag_facas.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_snapshot_facas_v2(p_rows JSONB)
  RETURNS INT
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO printag_facas
    (nro_os, faca,
     lado_1, lado_2, montagem, medida_total,
     l1_total, l2_total, fto_final, fto_impr,
     l1_substrato, l2_substrato, l1_corte, l2_corte)
  SELECT
    NULLIF(REGEXP_REPLACE(COALESCE(trim(r.nro_os), ''), '^0+', ''), ''),
    NULLIF(trim(r.faca), ''),
    NULLIF(r.lado_1,      '')::NUMERIC,
    NULLIF(r.lado_2,      '')::NUMERIC,
    NULLIF(r.montagem,    '')::INT,
    NULLIF(trim(r.medida_total), ''),
    NULLIF(r.l1_total,    '')::NUMERIC,
    NULLIF(r.l2_total,    '')::NUMERIC,
    NULLIF(r.fto_final,   '')::INT,
    NULLIF(r.fto_impr,    '')::INT,
    NULLIF(r.l1_substrato,'')::NUMERIC,
    NULLIF(r.l2_substrato,'')::NUMERIC,
    NULLIF(r.l1_corte,    '')::NUMERIC,
    NULLIF(r.l2_corte,    '')::NUMERIC
  FROM jsonb_to_recordset(p_rows) AS r(
    nro_os       TEXT,
    faca         TEXT,
    lado_1       TEXT,
    lado_2       TEXT,
    montagem     TEXT,
    medida_total TEXT,
    l1_total     TEXT,
    l2_total     TEXT,
    fto_final    TEXT,
    fto_impr     TEXT,
    l1_substrato TEXT,
    l2_substrato TEXT,
    l1_corte     TEXT,
    l2_corte     TEXT
  )
  WHERE r.nro_os IS NOT NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- =========================================================
-- 5. printag_refresh_base
-- Refresha a MV após upload. Chamado pelo frontend depois
-- das 3 funções de snapshot.
-- Se a MV estiver vazia (primeira carga), usa refresh normal;
-- caso contrário usa CONCURRENTLY para não travar leituras.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_refresh_base()
  RETURNS VOID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET statement_timeout = 0
AS $$
BEGIN
  IF (SELECT ispopulated FROM pg_matviews WHERE matviewname = 'mv_base_apontamentos') THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_base_apontamentos;
  ELSE
    REFRESH MATERIALIZED VIEW mv_base_apontamentos;
  END IF;
END;
$$;

-- =====================================================================
-- 029_agente_multiarea.sql
--
-- Depois da 024 a base tem 10 máquinas em 5 áreas, mas as RPCs do agente
-- ainda tratam tudo como uma coisa só: printag_filtros_agente devolve
-- máquina sem área, e printag_rank_dimensao não sabe agrupar por área.
-- Resultado: o agente ou responde misturando Impressão com Acabamento,
-- ou precisa do mapa máquina→área chumbado no system prompt — que foi
-- exatamente o que envelheceu quando as 7 máquinas novas entraram.
--
-- As duas mudanças são de conteúdo, não de assinatura:
--   - filtros_agente: `maquinas` continua JSON, só ganha a chave area;
--   - rank_dimensao:  um novo ramo no CASE, RETURNS TABLE intacto.
-- Logo CREATE OR REPLACE basta nas duas, sem DROP.
--
-- Do lado do n8n nada muda: a tool filtros_disponiveis faz
-- `SELECT maquinas, ...` (repassa o JSON inteiro) e rank_dimensao recebe
-- p_dimensao como texto livre.
-- =====================================================================

-- =======  UP  ========

-- =========================================================
-- 1. printag_filtros_agente
-- Cada máquina passa a vir com a área, para o agente resolver
-- "Impressão" → lista de maquinas_ids sem adivinhar.
-- =========================================================
-- Drop necessario: migration 031 altera o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_filtros_agente(INT);

CREATE OR REPLACE FUNCTION printag_filtros_agente(p_ano INT DEFAULT NULL)
RETURNS TABLE (
  maquinas     JSON,
  operadores   JSON,
  tipos_acabam JSON,
  semanas      JSON,
  meses        JSON,
  anos         JSON
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (SELECT json_agg(r ORDER BY r.area, r.nome)
     FROM (SELECT DISTINCT maquina_id AS id, nome_maquina AS nome, area
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS maquinas,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT operador AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND operador IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS operadores,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT tipo_acabamento AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND tipo_acabamento IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS tipos_acabam,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT semana AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS semanas,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT mes AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS meses,

    (SELECT json_agg(r ORDER BY r DESC)
     FROM (SELECT DISTINCT ano AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL) r)                  AS anos;
$$;

-- =========================================================
-- 2. printag_rank_dimensao
-- Acrescenta a dimensão 'area'. Corpo idêntico ao da 023 fora
-- os dois CASE (projeção e guarda de NOT NULL).
-- =========================================================
CREATE OR REPLACE FUNCTION printag_rank_dimensao(
  p_dimensao     TEXT    DEFAULT 'operador',
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  item                     TEXT,
  item_id                  INT,
  acerto_hrs               NUMERIC,
  quantidade_acerto        BIGINT,
  tempo_medio_acerto_h     NUMERIC,
  meta_acerto_total        NUMERIC,
  desvio_acerto_h          NUMERIC,
  virando_hrs              NUMERIC,
  produzido_virando        BIGINT,
  vel_real_pech            NUMERIC,
  vel_meta_pech            NUMERIC,
  vel_produzindo_pech      NUMERIC,
  improd_area_h            NUMERIC,
  meta_improd_area_h       NUMERIC,
  improd_pct               NUMERIC,
  improd_gerencial_h       NUMERIC,
  improd_ger_pct           NUMERIC,
  tiragem_media_pec_acerto NUMERIC,
  produzido_total          BIGINT,
  tempo_total              NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE lower(COALESCE(p_dimensao,'operador'))
      WHEN 'maquina'         THEN nome_maquina
      WHEN 'máquina'         THEN nome_maquina
      WHEN 'area'            THEN area
      WHEN 'área'            THEN area
      WHEN 'tipo_acabamento' THEN tipo_acabamento
      WHEN 'acabamento'      THEN tipo_acabamento
      WHEN 'os'              THEN nro_os
      WHEN 'produto'         THEN titulo_produto
      WHEN 'cliente'         THEN nome_cliente
      WHEN 'faca'            THEN numero_faca
      ELSE operador
    END                                                      AS item,
    CASE WHEN lower(COALESCE(p_dimensao,'operador')) IN ('maquina','máquina')
         THEN MAX(maquina_id) END                            AS item_id,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    SUM(quantidade_acerto)::BIGINT                           AS quantidade_acerto,
    ROUND((SUM(acerto_hrs)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 2) AS tempo_medio_acerto_h,
    ROUND(SUM(meta_acerto)::NUMERIC, 2)                      AS meta_acerto_total,
    ROUND((SUM(acerto_hrs) - SUM(meta_acerto))::NUMERIC, 2)  AS desvio_acerto_h,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(qtd_produzida_meta_vel_virando)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_meta_pech,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS vel_produzindo_pech,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC, 2)              AS meta_improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS improd_pct,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 2)     AS improd_gerencial_h,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                      AS tempo_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (CASE lower(COALESCE(p_dimensao,'operador'))
           WHEN 'maquina'         THEN nome_maquina
           WHEN 'máquina'         THEN nome_maquina
           WHEN 'area'            THEN area
           WHEN 'área'            THEN area
           WHEN 'tipo_acabamento' THEN tipo_acabamento
           WHEN 'acabamento'      THEN tipo_acabamento
           WHEN 'os'              THEN nro_os
           WHEN 'produto'         THEN titulo_produto
           WHEN 'cliente'         THEN nome_cliente
           WHEN 'faca'            THEN numero_faca
           ELSE operador
         END) IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY 1
  ORDER BY 1;
$$;

-- ---- Permissões ----
GRANT EXECUTE ON FUNCTION printag_filtros_agente(INT)                                          TO authenticated;
GRANT EXECUTE ON FUNCTION printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[]) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Conferência:
--   SELECT maquinas FROM printag_filtros_agente(2026);
--     → cada item com id, nome e area
--   SELECT item, tempo_total FROM printag_rank_dimensao('area', 2026);
--     → uma linha por área
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- Reaplicar printag_filtros_agente da 016 e printag_rank_dimensao da 023.

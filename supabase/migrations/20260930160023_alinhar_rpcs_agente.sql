-- =====================================================================
-- 023_alinhar_rpcs_agente.sql
--
-- O agente e o dashboard vinham calculando os mesmos indicadores com
-- fórmulas diferentes. As RPCs de 016 ficaram na versão antiga:
--
--   improd_pct          agente: área / virando
--                       dash  : área / (virando + área)          [019/020]
--   improd gerencial %  agente: não existia
--                       dash  : ger / (virando+acerto+área+ger)  [020]
--   vel. produzindo     agente: não existia
--                       dash  : prod_virando / (virando+acerto+área+ger) [017]
--   tiragem média       agente: derivável, mas nunca exposta
--                       dash  : produzido_total / quantidade_acerto
--
-- Esta migration traz a camada do agente para as fórmulas do dashboard.
--
-- ESCOPO — LEIA ANTES DE APLICAR:
--   Mexe SOMENTE nas funções de 016, que são exclusivas do agente n8n.
--   `front/front.html` não referencia nenhuma delas: o dashboard usa
--   printag_ind_* / printag_indm_* (011, 014, 017, 019, 020), que esta
--   migration NÃO toca. A mv_base_apontamentos também não é alterada.
--
-- Assinaturas (nomes e ordem dos parâmetros) preservadas, para não
-- quebrar as chamadas nomeadas dos nós Postgres do n8n.
--
-- Dependência: aplicar depois de 016.
-- =====================================================================

-- =======  UP  ========

-- =========================================================
-- 1. printag_kpi_periodo
-- +improd_ger_pct, +improd_gerencial_h, +tiragem_media_pec_acerto,
-- +vel_produzindo_pech; improd_pct e meta_improd_pct corrigidos.
-- =========================================================
DROP FUNCTION IF EXISTS printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_kpi_periodo(
  p_gran         TEXT    DEFAULT 'semana',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  periodo                  INT,
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
  meta_improd_pct          NUMERIC,
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
    CASE WHEN lower(COALESCE(p_gran,'semana')) IN ('mes','mês','mensal','m','month')
         THEN mes ELSE semana END                            AS periodo,
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
    -- Velocidade Média Produzindo: mesmo numerador da velocidade virando,
    -- mas dividido pelas 4 famílias de hora do gráfico chartIndVelocAcerto.
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
    -- Mesmo denominador do real, para a comparação ser direta.
    ROUND((SUM(meta_horas_imp_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS meta_improd_pct,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 2)     AS improd_gerencial_h,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    -- Tiragem: peças por evento de acerto (gráfico chartIndTiragem).
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                      AS tempo_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_periodos     IS NULL
         OR (CASE WHEN lower(COALESCE(p_gran,'semana')) IN ('mes','mês','mensal','m','month')
                  THEN mes ELSE semana END) = ANY(p_periodos))
  GROUP BY 1
  ORDER BY 1;
$$;


-- =========================================================
-- 2. printag_kpi_yoy
-- improd_pct corrigido + vel_produzindo_pech, para a comparação
-- anual não misturar duas fórmulas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_kpi_yoy(
  p_gran         TEXT    DEFAULT 'mes',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                      INT,
  periodo                  INT,
  acerto_hrs               NUMERIC,
  virando_hrs              NUMERIC,
  produzido_virando        BIGINT,
  vel_real_pech            NUMERIC,
  vel_produzindo_pech      NUMERIC,
  improd_area_h            NUMERIC,
  improd_pct               NUMERIC,
  improd_ger_pct           NUMERIC,
  tiragem_media_pec_acerto NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ano,
    CASE WHEN lower(COALESCE(p_gran,'mes')) IN ('mes','mês','mensal','m','month')
         THEN mes ELSE semana END                            AS periodo,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS vel_produzindo_pech,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS improd_pct,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano IN (p_ano, p_ano - 1))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_periodos     IS NULL
         OR (CASE WHEN lower(COALESCE(p_gran,'mes')) IN ('mes','mês','mensal','m','month')
                  THEN mes ELSE semana END) = ANY(p_periodos))
  GROUP BY ano, 2
  ORDER BY ano, 2;
$$;


-- =========================================================
-- 3. printag_rank_dimensao
-- Mesmas colunas derivadas, para os rankings baterem com o painel.
-- Dimensões novas: os, produto, cliente e faca.
-- =========================================================
DROP FUNCTION IF EXISTS printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[]);

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


-- ---------------------------------------------------------
-- Permissões
-- O DROP levou os GRANT junto; precisam ser refeitos.
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[])          TO authenticated;
GRANT EXECUTE ON FUNCTION printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[])              TO authenticated;
GRANT EXECUTE ON FUNCTION printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[]) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------
-- Conferência — os números devem bater com os gráficos:
--   SELECT periodo, vel_produzindo_pech, tiragem_media_pec_acerto,
--          improd_pct, improd_ger_pct
--   FROM printag_kpi_periodo('semana', 2026, ARRAY[7,19]);
-- S19 vel_produzindo_pech ≈ 21115 · S7 tiragem ≈ 69404
--
-- Sanidade do dashboard (deve continuar idêntico):
--   SELECT * FROM printag_ind_improdutivos_semana(2026, NULL, NULL, NULL, NULL);
-- ---------------------------------------------------------


-- =======  DOWN  ========
-- Reaplicar 016_rpcs_consolidadas_agente.sql restaura as três funções
-- na versão antiga (fórmulas desalinhadas do dashboard).

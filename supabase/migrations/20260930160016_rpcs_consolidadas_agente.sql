-- =========================================================
-- PrintAG — 016: RPCs CONSOLIDADAS (camada do agente de IA)
--
-- Objetivo: reduzir a superfície de tools do agente de 19 para 6,
-- unificando os pares semanal/mensal (`ind_*` / `indm_*`) e os
-- rankings por dimensão em funções com parâmetro discriminador.
--
-- ATENÇÃO: esta migration é ADITIVA. As funções de 011 e 014
-- continuam existindo e são as que alimentam o dashboard
-- (`front/front.html`). Nada aqui altera ou substitui aquelas.
--
-- Somente leitura sobre mv_base_apontamentos. A MV não é alterada.
--
-- Parâmetros comuns:
--   p_gran         TEXT    — 'semana' (padrão) ou 'mes'
--   p_ano          INT     — ano (NULL = todos)
--   p_periodos     INT[]   — semanas ISO ou meses 1-12, conforme p_gran
--   p_maquinas     INT[]   — IDs de printiag_maquinas (NULL = todas)
--   p_tipos_acabam TEXT[]  — tipo_acabamento (NULL = todos)
--   p_operadores   TEXT[]  — operador (NULL = todos)
-- =========================================================

-- =========================================================
-- 1. printag_kpi_periodo
-- Painel único de KPIs por período (semana OU mês).
-- Substitui, para o agente: ind_acerto_semana, ind_improdutivos_semana,
-- ind_veloc_virando_semana, ind_qtd_tiragem e seus equivalentes mensais.
-- =========================================================
-- Drop necessario: migration 023 altera o tipo de retorno desta funcao.
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
  periodo              INT,
  acerto_hrs           NUMERIC,
  quantidade_acerto    BIGINT,
  tempo_medio_acerto_h NUMERIC,
  meta_acerto_total    NUMERIC,
  desvio_acerto_h      NUMERIC,
  virando_hrs          NUMERIC,
  produzido_virando    BIGINT,
  vel_real_pech        NUMERIC,
  vel_meta_pech        NUMERIC,
  improd_area_h        NUMERIC,
  meta_improd_area_h   NUMERIC,
  improd_pct           NUMERIC,
  meta_improd_pct      NUMERIC,
  produzido_total      BIGINT,
  tempo_total          NUMERIC
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
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC, 2)              AS meta_improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS improd_pct,
    ROUND((SUM(meta_horas_imp_area) * 100
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS meta_improd_pct,
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
-- 2. printag_kpi_disponibilidade
-- Cascata de disponibilidade por período (semana OU mês).
-- Substitui, para o agente: ind_disponibilidade / indm_disponibilidade.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_kpi_disponibilidade(
  p_gran         TEXT    DEFAULT 'semana',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  periodo                   INT,
  tempo_total               NUMERIC,
  virando_hrs               NUMERIC,
  acerto_hrs                NUMERIC,
  operacional_planejado_hrs NUMERIC,
  problemas_de_processo_hrs NUMERIC,
  manutencao_corretiva_hrs  NUMERIC,
  manutencao_preventiva_hrs NUMERIC,
  aguardando_hrs            NUMERIC,
  sem_tripulacao_hrs        NUMERIC,
  sem_servico_hrs           NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE WHEN lower(COALESCE(p_gran,'semana')) IN ('mes','mês','mensal','m','month')
         THEN mes ELSE semana END                        AS periodo,
    ROUND(SUM(tempo_total)::NUMERIC,               2) AS tempo_total,
    ROUND(SUM(virando_hrs)::NUMERIC,               2) AS virando_hrs,
    ROUND(SUM(acerto_hrs)::NUMERIC,                2) AS acerto_hrs,
    ROUND(SUM(operacional_planejado_hrs)::NUMERIC, 2) AS operacional_planejado_hrs,
    ROUND(SUM(problemas_de_processo_hrs)::NUMERIC, 2) AS problemas_de_processo_hrs,
    ROUND(SUM(manutencao_corretiva_hrs)::NUMERIC,  2) AS manutencao_corretiva_hrs,
    ROUND(SUM(manutencao_preventiva_hrs)::NUMERIC, 2) AS manutencao_preventiva_hrs,
    ROUND(SUM(aguardando_hrs)::NUMERIC,            2) AS aguardando_hrs,
    ROUND(SUM(sem_tripulacao_hrs)::NUMERIC,        2) AS sem_tripulacao_hrs,
    ROUND(SUM(sem_servico_hrs)::NUMERIC,           2) AS sem_servico_hrs
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
-- 3. printag_kpi_yoy
-- Comparativo ano atual vs ano anterior, por semana ou mês.
-- Substitui, para o agente: ind_velocidade_com_acerto.
-- =========================================================
-- Drop necessario: migration 023 altera o tipo de retorno desta funcao.
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
  ano               INT,
  periodo           INT,
  acerto_hrs        NUMERIC,
  virando_hrs       NUMERIC,
  produzido_virando BIGINT,
  vel_real_pech     NUMERIC,
  improd_area_h     NUMERIC,
  improd_pct        NUMERIC
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
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS improd_pct
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
-- 4. printag_rank_dimensao
-- Ranking/quebra por dimensão, escolhida em p_dimensao:
--   'operador' (padrão) | 'maquina' | 'tipo_acabamento'
-- Substitui, para o agente: rank_operadores, rank_maquinas,
-- rank_tipo_acabamento (015).
-- =========================================================
-- Drop necessario: migration 023 altera o tipo de retorno desta funcao.
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
  item                 TEXT,
  item_id              INT,
  acerto_hrs           NUMERIC,
  quantidade_acerto    BIGINT,
  tempo_medio_acerto_h NUMERIC,
  meta_acerto_total    NUMERIC,
  desvio_acerto_h      NUMERIC,
  virando_hrs          NUMERIC,
  produzido_virando    BIGINT,
  vel_real_pech        NUMERIC,
  vel_meta_pech        NUMERIC,
  improd_area_h        NUMERIC,
  meta_improd_area_h   NUMERIC,
  improd_pct           NUMERIC,
  improd_gerencial_h   NUMERIC,
  tempo_total          NUMERIC
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
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC, 2)              AS meta_improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS improd_pct,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 2)     AS improd_gerencial_h,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                      AS tempo_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (CASE lower(COALESCE(p_dimensao,'operador'))
           WHEN 'maquina'         THEN nome_maquina
           WHEN 'máquina'         THEN nome_maquina
           WHEN 'tipo_acabamento' THEN tipo_acabamento
           WHEN 'acabamento'      THEN tipo_acabamento
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

-- =========================================================
-- 5. printag_filtros_agente
-- Valores disponíveis para o agente montar filtros:
-- máquinas (id + nome), operadores, tipos de acabamento,
-- semanas, meses e anos com dados.
-- Substitui, para o agente: ind_filtros + indm_filtros.
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
    (SELECT json_agg(r ORDER BY r.nome)
     FROM (SELECT DISTINCT maquina_id AS id, nome_maquina AS nome
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

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[])         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_kpi_disponibilidade(TEXT, INT, INT[], INT[], TEXT[], TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[])             TO authenticated;
GRANT EXECUTE ON FUNCTION printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_filtros_agente(INT)                                          TO authenticated;

NOTIFY pgrst, 'reload schema';

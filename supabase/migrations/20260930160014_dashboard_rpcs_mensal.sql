-- =========================================================
-- PrintAG — 014: RPCs de Dashboard — Indicadores por Mês
-- Espelho de 011_dashboard_rpcs.sql com granularidade MENSAL.
--
-- Assinatura padrão de filtros para todos os RPCs:
--   p_ano          INT     — ano (obrigatório recomendado)
--   p_meses        INT[]   — meses (1..12) a incluir (NULL = todos)
--   p_maquinas     INT[]   — IDs de printiag_maquinas (NULL = todas)
--   p_tipos_acabam TEXT[]  — tipo_acabamento (NULL = todos)
--   p_operadores   TEXT[]  — operador (NULL = todos)
--
-- IMPORTANTE: esta migration é SOMENTE LEITURA sobre mv_base_apontamentos.
-- Não cria, altera, indexa nem atualiza a materialized view.
-- =========================================================

-- =========================================================
-- 1. printag_indm_acerto_mes
-- Indicador de Acerto: horas de setup vs meta por mês.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_acerto_mes(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes                 INT,
  acerto_hrs          NUMERIC,
  quantidade_acerto   BIGINT,
  meta_acerto_total   NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    ROUND(SUM(acerto_hrs)::NUMERIC,        4) AS acerto_hrs,
    SUM(quantidade_acerto)                    AS quantidade_acerto,
    ROUND(SUM(meta_acerto)::NUMERIC,       4) AS meta_acerto_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY mes
  ORDER BY mes;
$$;

-- =========================================================
-- 2. printag_indm_veloc_virando_mes
-- Indicador de Velocidade em Virando: real vs meta.
-- produzido_virando = peças reais produzidas em apontamentos Virando.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_veloc_virando_mes(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes                            INT,
  produzido_virando              BIGINT,
  virando_hrs                    NUMERIC,
  qtd_produzida_meta_vel_virando NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND(SUM(virando_hrs)::NUMERIC,                      4) AS virando_hrs,
    ROUND(SUM(qtd_produzida_meta_vel_virando)::NUMERIC,   4) AS qtd_produzida_meta_vel_virando
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY mes
  ORDER BY mes;
$$;

-- =========================================================
-- 3. printag_indm_improdutivos_mes
-- Indicador de Horas Improdutivas por Área vs meta.
-- =========================================================
-- Drop necessario: migration 020 altera o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_indm_improdutivos_mes(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_indm_improdutivos_mes(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes                     INT,
  horas_improdutivas_area NUMERIC,
  virando_hrs             NUMERIC,
  meta_horas_imp_area     NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 4) AS horas_improdutivas_area,
    ROUND(SUM(virando_hrs)::NUMERIC,             4) AS virando_hrs,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC,     4) AS meta_horas_imp_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY mes
  ORDER BY mes;
$$;

-- =========================================================
-- 4. printag_indm_pareto_area
-- Pareto de perdas Área: ranking de motivos por horas improdutivas.
-- Trava no ÚLTIMO mês do período selecionado.
-- Inclui apontamentos com classificação 'Área' ou 'Virando'.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_pareto_area(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  apontamento             TEXT,
  horas_improdutivas_area NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    apontamento,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 4) AS horas_improdutivas_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND classificacao_oee IN ('Área', 'Virando')
    AND mes = (
      SELECT MAX(mes) FROM mv_base_apontamentos
      WHERE maquina_id IS NOT NULL
        AND (p_ano          IS NULL OR ano        =  p_ano)
        AND (p_meses        IS NULL OR mes        = ANY(p_meses))
        AND (p_maquinas     IS NULL OR maquina_id = ANY(p_maquinas))
        AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
        AND (p_operadores   IS NULL OR operador   = ANY(p_operadores))
    )
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY apontamento
  ORDER BY SUM(horas_improdutivas_area) DESC NULLS LAST;
$$;

-- =========================================================
-- 5. printag_indm_pareto_gerencial
-- Pareto de perdas Gerencial: ranking de motivos.
-- Trava no ÚLTIMO mês do período selecionado.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_pareto_gerencial(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  apontamento                  TEXT,
  horas_improdutivas_gerencial NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    apontamento,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 4) AS horas_improdutivas_gerencial
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND classificacao_oee = 'Gerencial'
    AND mes = (
      SELECT MAX(mes) FROM mv_base_apontamentos
      WHERE maquina_id IS NOT NULL
        AND (p_ano          IS NULL OR ano        =  p_ano)
        AND (p_meses        IS NULL OR mes        = ANY(p_meses))
        AND (p_maquinas     IS NULL OR maquina_id = ANY(p_maquinas))
        AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
        AND (p_operadores   IS NULL OR operador   = ANY(p_operadores))
    )
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY apontamento
  ORDER BY SUM(horas_improdutivas_gerencial) DESC NULLS LAST;
$$;

-- =========================================================
-- 6. printag_indm_velocidade_com_acerto
-- Comparativo ano atual vs ano anterior por mês.
-- Retorna linhas com o campo 'ano' para o frontend separar.
-- =========================================================
-- Drop necessario: migration 017 altera o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_indm_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_indm_velocidade_com_acerto(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                     INT,
  mes                     INT,
  produzido_virando       BIGINT,
  acerto_hrs              NUMERIC,
  virando_hrs             NUMERIC,
  horas_improdutivas_area NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ano,
    mes,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)        AS produzido_virando,
    ROUND(SUM(acerto_hrs)::NUMERIC,                           4) AS acerto_hrs,
    ROUND(SUM(virando_hrs)::NUMERIC,                          4) AS virando_hrs,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,              4) AS horas_improdutivas_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano IS NULL OR ano IN (p_ano, p_ano - 1))
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY ano, mes
  ORDER BY ano, mes;
$$;

-- =========================================================
-- 7. printag_indm_qtd_tiragem
-- Quantidade produzida e número de acertos por mês.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_qtd_tiragem(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes               INT,
  produzido_total   BIGINT,
  quantidade_acerto BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    SUM(produzido)         AS produzido_total,
    SUM(quantidade_acerto) AS quantidade_acerto
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY mes
  ORDER BY mes;
$$;

-- =========================================================
-- 8. printag_indm_disponibilidade
-- Cascata de disponibilidade: horas por categoria de perda.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_disponibilidade(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes                          INT,
  virando_hrs                  NUMERIC,
  acerto_hrs                   NUMERIC,
  tempo_total                  NUMERIC,
  operacional_planejado_hrs    NUMERIC,
  problemas_de_processo_hrs    NUMERIC,
  manutencao_corretiva_hrs     NUMERIC,
  manutencao_preventiva_hrs    NUMERIC,
  aguardando_hrs               NUMERIC,
  sem_tripulacao_hrs           NUMERIC,
  sem_servico_hrs              NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    ROUND(SUM(virando_hrs)::NUMERIC,               4) AS virando_hrs,
    ROUND(SUM(acerto_hrs)::NUMERIC,                4) AS acerto_hrs,
    ROUND(SUM(tempo_total)::NUMERIC,               4) AS tempo_total,
    ROUND(SUM(operacional_planejado_hrs)::NUMERIC, 4) AS operacional_planejado_hrs,
    ROUND(SUM(problemas_de_processo_hrs)::NUMERIC, 4) AS problemas_de_processo_hrs,
    ROUND(SUM(manutencao_corretiva_hrs)::NUMERIC,  4) AS manutencao_corretiva_hrs,
    ROUND(SUM(manutencao_preventiva_hrs)::NUMERIC, 4) AS manutencao_preventiva_hrs,
    ROUND(SUM(aguardando_hrs)::NUMERIC,            4) AS aguardando_hrs,
    ROUND(SUM(sem_tripulacao_hrs)::NUMERIC,        4) AS sem_tripulacao_hrs,
    ROUND(SUM(sem_servico_hrs)::NUMERIC,           4) AS sem_servico_hrs
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY mes
  ORDER BY mes;
$$;

-- =========================================================
-- 9. printag_indm_filtros
-- Retorna listas de valores disponíveis para preencher os
-- dropdowns de filtro do dashboard mensal.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_indm_filtros(p_ano INT DEFAULT NULL)
RETURNS TABLE (
  maquinas      JSON,
  tipos_acabam  JSON,
  operadores    JSON,
  meses         JSON,
  anos          JSON
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (SELECT json_agg(r ORDER BY r.nome)
     FROM (
       SELECT DISTINCT maquina_id AS id, nome_maquina AS nome
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
         AND (p_ano IS NULL OR ano = p_ano)
     ) r)                                                     AS maquinas,

    (SELECT json_agg(r ORDER BY r)
     FROM (
       SELECT DISTINCT tipo_acabamento AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
         AND tipo_acabamento IS NOT NULL
         AND (p_ano IS NULL OR ano = p_ano)
     ) r)                                                     AS tipos_acabam,

    (SELECT json_agg(r ORDER BY r)
     FROM (
       SELECT DISTINCT operador AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
         AND operador IS NOT NULL
         AND (p_ano IS NULL OR ano = p_ano)
     ) r)                                                     AS operadores,

    (SELECT json_agg(r ORDER BY r)
     FROM (
       SELECT DISTINCT mes AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
         AND (p_ano IS NULL OR ano = p_ano)
     ) r)                                                     AS meses,

    (SELECT json_agg(r ORDER BY r DESC)
     FROM (
       SELECT DISTINCT ano AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
     ) r)                                                     AS anos;
$$;

-- =========================================================
-- GRANTS
-- =========================================================
GRANT EXECUTE ON FUNCTION printag_indm_acerto_mes(INT, INT[], INT[], TEXT[], TEXT[])          TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_veloc_virando_mes(INT, INT[], INT[], TEXT[], TEXT[])   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_improdutivos_mes(INT, INT[], INT[], TEXT[], TEXT[])    TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_pareto_area(INT, INT[], INT[], TEXT[], TEXT[])         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_pareto_gerencial(INT, INT[], INT[], TEXT[], TEXT[])    TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_qtd_tiragem(INT, INT[], INT[], TEXT[], TEXT[])         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_disponibilidade(INT, INT[], INT[], TEXT[], TEXT[])     TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_filtros(INT)                                          TO authenticated;

NOTIFY pgrst, 'reload schema';

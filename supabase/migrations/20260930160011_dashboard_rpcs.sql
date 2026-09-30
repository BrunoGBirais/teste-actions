-- =========================================================
-- PrintAG — 011: RPCs de Dashboard — Indicadores por Semana
-- Assinatura padrão de filtros para todos os RPCs:
--   p_ano          INT     — ano (obrigatório recomendado)
--   p_semanas      INT[]   — semanas ISO a incluir (NULL = todas)
--   p_maquinas     INT[]   — IDs de printiag_maquinas (NULL = todas)
--   p_tipos_acabam TEXT[]  — tipo_acabamento (NULL = todos)
--   p_operadores   TEXT[]  — operador (NULL = todos)
-- =========================================================

-- =========================================================
-- 1. printag_ind_acerto_semana
-- Indicador de Acerto: horas de setup vs meta por semana.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_acerto_semana(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana              INT,
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
    semana,
    ROUND(SUM(acerto_hrs)::NUMERIC,        4) AS acerto_hrs,
    SUM(quantidade_acerto)                    AS quantidade_acerto,
    ROUND(SUM(meta_acerto)::NUMERIC,       4) AS meta_acerto_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 2. printag_ind_veloc_virando_semana
-- Indicador de Velocidade em Virando: real vs meta.
-- produzido_virando = peças reais produzidas em apontamentos Virando.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_veloc_virando_semana(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana                        INT,
  produzido_virando             BIGINT,
  virando_hrs                   NUMERIC,
  qtd_produzida_meta_vel_virando NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    semana,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND(SUM(virando_hrs)::NUMERIC,                      4) AS virando_hrs,
    ROUND(SUM(qtd_produzida_meta_vel_virando)::NUMERIC,   4) AS qtd_produzida_meta_vel_virando
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 3. printag_ind_improdutivos_semana
-- Indicador de Horas Improdutivas por Área vs meta.
-- =========================================================
-- DROP explícito: migrations posteriores (020) mudam as colunas de saída,
-- e CREATE OR REPLACE não permite alterar o tipo de retorno (OUT params).
DROP FUNCTION IF EXISTS printag_ind_improdutivos_semana(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_ind_improdutivos_semana(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana                  INT,
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
    semana,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 4) AS horas_improdutivas_area,
    ROUND(SUM(virando_hrs)::NUMERIC,             4) AS virando_hrs,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC,     4) AS meta_horas_imp_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 4. printag_ind_pareto_area
-- Pareto de perdas Área: ranking de motivos por horas improdutivas.
-- Inclui apontamentos com classificação 'Área' ou 'Virando'.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_pareto_area(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
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
    AND semana = (
      SELECT MAX(semana) FROM mv_base_apontamentos
      WHERE maquina_id IS NOT NULL
        AND (p_ano          IS NULL OR ano       =  p_ano)
        AND (p_semanas      IS NULL OR semana     = ANY(p_semanas))
        AND (p_maquinas     IS NULL OR maquina_id = ANY(p_maquinas))
        AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
        AND (p_operadores   IS NULL OR operador   = ANY(p_operadores))
    )
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY apontamento
  ORDER BY SUM(horas_improdutivas_area) DESC NULLS LAST;
$$;

-- =========================================================
-- 5. printag_ind_pareto_gerencial
-- Pareto de perdas Gerencial: ranking de motivos.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_pareto_gerencial(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
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
    AND semana = (
      SELECT MAX(semana) FROM mv_base_apontamentos
      WHERE maquina_id IS NOT NULL
        AND (p_ano          IS NULL OR ano       =  p_ano)
        AND (p_semanas      IS NULL OR semana     = ANY(p_semanas))
        AND (p_maquinas     IS NULL OR maquina_id = ANY(p_maquinas))
        AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
        AND (p_operadores   IS NULL OR operador   = ANY(p_operadores))
    )
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY apontamento
  ORDER BY SUM(horas_improdutivas_gerencial) DESC NULLS LAST;
$$;

-- =========================================================
-- 6. printag_ind_velocidade_com_acerto
-- Comparativo ano atual vs ano anterior por semana.
-- Retorna linhas com o campo 'ano' para o frontend separar.
-- =========================================================
-- Drop necessario: migration 017 altera o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_ind_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_ind_velocidade_com_acerto(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                     INT,
  semana                  INT,
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
    semana,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)        AS produzido_virando,
    ROUND(SUM(acerto_hrs)::NUMERIC,                           4) AS acerto_hrs,
    ROUND(SUM(virando_hrs)::NUMERIC,                          4) AS virando_hrs,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,              4) AS horas_improdutivas_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano IS NULL OR ano IN (p_ano, p_ano - 1))
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY ano, semana
  ORDER BY ano, semana;
$$;

-- =========================================================
-- 7. printag_ind_qtd_tiragem
-- Quantidade produzida e número de acertos por semana.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_qtd_tiragem(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana            INT,
  produzido_total   BIGINT,
  quantidade_acerto BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    semana,
    SUM(produzido)        AS produzido_total,
    SUM(quantidade_acerto) AS quantidade_acerto
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 8. printag_ind_disponibilidade
-- Cascata de disponibilidade: horas por categoria de perda.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_disponibilidade(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana                       INT,
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
    semana,
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
    AND (p_ano          IS NULL OR ano            =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 9. printag_ind_filtros
-- Retorna listas de valores disponíveis para preencher os
-- dropdowns de filtro do dashboard.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_ind_filtros(p_ano INT DEFAULT NULL)
RETURNS TABLE (
  maquinas      JSON,
  tipos_acabam  JSON,
  operadores    JSON,
  semanas       JSON,
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
       SELECT DISTINCT semana AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
         AND (p_ano IS NULL OR ano = p_ano)
     ) r)                                                     AS semanas,

    (SELECT json_agg(r ORDER BY r DESC)
     FROM (
       SELECT DISTINCT ano AS r
       FROM mv_base_apontamentos
       WHERE maquina_id IS NOT NULL
     ) r)                                                     AS anos;
$$;

-- =========================================================
-- PrintAG — 017: correção da Velocidade + Acerto
--
-- As RPCs printag_ind_velocidade_com_acerto (011) e
-- printag_indm_velocidade_com_acerto (014) não expunham
-- horas_improdutivas_gerencial, então o frontend acabava dividindo
-- a produção apenas por virando_hrs — o que fazia o gráfico
-- "Velocidade + Acerto" repetir exatamente os valores do gráfico
-- "Velocidade Média Virando".
--
-- Fórmula correta do indicador:
--   qtd_produzida / (virando + acerto + improdutivos área + improdutivos gerenciais)
--
-- Esta migration apenas acrescenta a coluna que faltava no retorno.
-- O DROP é obrigatório: Postgres não permite CREATE OR REPLACE
-- FUNCTION alterando o RETURNS TABLE.
--
-- Somente leitura sobre mv_base_apontamentos. Nenhuma alteração na MV.
-- =========================================================

-- =========================================================
-- 1. printag_ind_velocidade_com_acerto (semanal)
-- Comparativo ano atual vs ano anterior por semana.
-- Retorna linhas com o campo 'ano' para o frontend separar.
-- =========================================================
DROP FUNCTION IF EXISTS printag_ind_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_ind_velocidade_com_acerto(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                          INT,
  semana                       INT,
  produzido_virando            BIGINT,
  acerto_hrs                   NUMERIC,
  virando_hrs                  NUMERIC,
  horas_improdutivas_area      NUMERIC,
  horas_improdutivas_gerencial NUMERIC
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
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,              4) AS horas_improdutivas_area,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC,         4) AS horas_improdutivas_gerencial
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
-- 2. printag_indm_velocidade_com_acerto (mensal)
-- Comparativo ano atual vs ano anterior por mês.
-- Retorna linhas com o campo 'ano' para o frontend separar.
-- =========================================================
DROP FUNCTION IF EXISTS printag_indm_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_indm_velocidade_com_acerto(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                          INT,
  mes                          INT,
  produzido_virando            BIGINT,
  acerto_hrs                   NUMERIC,
  virando_hrs                  NUMERIC,
  horas_improdutivas_area      NUMERIC,
  horas_improdutivas_gerencial NUMERIC
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
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,              4) AS horas_improdutivas_area,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC,         4) AS horas_improdutivas_gerencial
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

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_ind_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[])  TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Restaura as assinaturas anteriores (sem horas_improdutivas_gerencial).
--
-- DROP FUNCTION IF EXISTS printag_ind_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);
-- DROP FUNCTION IF EXISTS printag_indm_velocidade_com_acerto(INT, INT[], INT[], TEXT[], TEXT[]);
-- -- reexecutar os blocos correspondentes de 011_dashboard_rpcs.sql e 014_dashboard_rpcs_mensal.sql
-- NOTIFY pgrst, 'reload schema';

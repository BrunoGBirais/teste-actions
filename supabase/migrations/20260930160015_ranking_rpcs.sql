-- =========================================================
-- PrintAG — 015: RPC de ranking de MOTIVOS DE PARADA
--
-- Pareto genérico de paradas com escopo configurável, válido para
-- o recorte inteiro (diferente dos paretos de 011/014, que olham
-- apenas o último período do filtro).
--
-- Responde perguntas do tipo:
--   "qual foi o maior motivo de parada do ano?"
--   "top causas de perda no mês X"
--   "por que a improdutividade da máquina Y piorou?"
--
-- As quebras por operador / máquina / tipo de acabamento ficam em
-- printag_rank_dimensao (migration 016).
--
-- Somente leitura sobre mv_base_apontamentos. Nenhuma alteração na MV.
--
-- Parâmetros:
--   p_ano          INT     — ano (NULL = todos)
--   p_escopo       TEXT    — 'area' (padrão) | 'gerencial' | 'todos'
--   p_semanas      INT[]   — semanas ISO (NULL = todas)
--   p_meses        INT[]   — meses 1-12 (NULL = todos)
--   p_maquinas     INT[]   — IDs de printiag_maquinas (NULL = todas)
--   p_tipos_acabam TEXT[]  — tipo_acabamento (NULL = todos)
--   p_operadores   TEXT[]  — operador (NULL = todos)
-- =========================================================

-- =========================================================
-- 1. printag_rank_motivos
-- Pareto genérico de motivos de parada, com escopo configurável.
-- p_escopo: 'area' | 'gerencial' | 'todos'
-- =========================================================
CREATE OR REPLACE FUNCTION printag_rank_motivos(
  p_ano          INT     DEFAULT NULL,
  p_escopo       TEXT    DEFAULT 'area',
  p_semanas      INT[]   DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  motivo       TEXT,
  horas        NUMERIC,
  ocorrencias  BIGINT,
  pct_do_total NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH filtrado AS (
    SELECT apontamento, tempo_total
    FROM mv_base_apontamentos
    WHERE maquina_id IS NOT NULL
      AND tempo_total IS NOT NULL
      AND (
            lower(COALESCE(p_escopo, 'area')) = 'todos'
         OR (lower(COALESCE(p_escopo, 'area')) = 'area'      AND classificacao_oee = 'Área')
         OR (lower(COALESCE(p_escopo, 'area')) = 'gerencial' AND classificacao_oee = 'Gerencial')
          )
      AND (p_ano          IS NULL OR ano             =  p_ano)
      AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
      AND (p_meses        IS NULL OR mes             = ANY(p_meses))
      AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
      AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
      AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  ),
  agregado AS (
    SELECT
      apontamento     AS motivo,
      SUM(tempo_total) AS horas,
      COUNT(*)::BIGINT AS ocorrencias
    FROM filtrado
    GROUP BY apontamento
  )
  SELECT
    motivo,
    ROUND(horas::NUMERIC, 2)                                                AS horas,
    ocorrencias,
    ROUND((100.0 * horas / NULLIF(SUM(horas) OVER (), 0))::NUMERIC, 2)      AS pct_do_total
  FROM agregado
  ORDER BY horas DESC;
$$;

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_rank_motivos(INT, TEXT, INT[], INT[], INT[], TEXT[], TEXT[])   TO authenticated;

NOTIFY pgrst, 'reload schema';

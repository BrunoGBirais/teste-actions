-- =========================================================
-- PrintAG — 020: Índice de Improdutivos Gerencial
--
-- O gráfico "Índice de Improdutivos Gerencial" vinha calculando
-- horas_improdutivas_area / virando_hrs. A fórmula correta é:
--
--   Improd. Gerencial / (Virando + Acerto + Improd. Área + Improd. Gerencial)
--
-- As RPCs de improdutivos passam a devolver acerto_hrs e
-- horas_improdutivas_gerencial, e a meta desse gráfico vira uma reta
-- editável ligada a meta_indisponibilidade_virando_gerencial (fração 0-1
-- no banco, exposta em % pelas RPCs), no mesmo padrão da migration 019.
--
-- RETURNS TABLE muda em todas elas, então DROP antes do CREATE.
-- =========================================================

-- =======  UP  ========

-- =========================================================
-- 1. printag_ind_improdutivos_semana
-- =========================================================
DROP FUNCTION IF EXISTS printag_ind_improdutivos_semana(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_ind_improdutivos_semana(
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  semana                       INT,
  horas_improdutivas_area      NUMERIC,
  horas_improdutivas_gerencial NUMERIC,
  virando_hrs                  NUMERIC,
  acerto_hrs                   NUMERIC,
  meta_horas_imp_area          NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    semana,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,      4) AS horas_improdutivas_area,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 4) AS horas_improdutivas_gerencial,
    ROUND(SUM(virando_hrs)::NUMERIC,                  4) AS virando_hrs,
    ROUND(SUM(acerto_hrs)::NUMERIC,                   4) AS acerto_hrs,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC,          4) AS meta_horas_imp_area
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
  GROUP BY semana
  ORDER BY semana;
$$;

-- =========================================================
-- 2. printag_indm_improdutivos_mes
-- =========================================================
DROP FUNCTION IF EXISTS printag_indm_improdutivos_mes(INT, INT[], INT[], TEXT[], TEXT[]);

CREATE OR REPLACE FUNCTION printag_indm_improdutivos_mes(
  p_ano          INT     DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  mes                          INT,
  horas_improdutivas_area      NUMERIC,
  horas_improdutivas_gerencial NUMERIC,
  virando_hrs                  NUMERIC,
  acerto_hrs                   NUMERIC,
  meta_horas_imp_area          NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mes,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC,      4) AS horas_improdutivas_area,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 4) AS horas_improdutivas_gerencial,
    ROUND(SUM(virando_hrs)::NUMERIC,                  4) AS virando_hrs,
    ROUND(SUM(acerto_hrs)::NUMERIC,                   4) AS acerto_hrs,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC,          4) AS meta_horas_imp_area
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
-- 3. printag_metas_fixas
-- Metas agregadas por média simples das máquinas selecionadas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);

CREATE OR REPLACE FUNCTION printag_metas_fixas(
  p_maquinas INT[] DEFAULT NULL
)
RETURNS TABLE (
  meta_velocidade_virando        NUMERIC,
  meta_velocidade_com_acerto     NUMERIC,
  meta_tempo_medio_acerto        NUMERIC,
  meta_improdutivo_area_pct      NUMERIC,
  meta_improdutivo_gerencial_pct NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ROUND(AVG(m.meta_velocidade_virando)::NUMERIC,    2) AS meta_velocidade_virando,
    ROUND(AVG(m.meta_velocidade_com_acerto)::NUMERIC, 2) AS meta_velocidade_com_acerto,
    ROUND(AVG(m.meta_tempo_medio_acerto)::NUMERIC,    2) AS meta_tempo_medio_acerto,
    ROUND((AVG(m.meta_indisponibilidade_virando_area)      * 100)::NUMERIC, 2) AS meta_improdutivo_area_pct,
    ROUND((AVG(m.meta_indisponibilidade_virando_gerencial) * 100)::NUMERIC, 2) AS meta_improdutivo_gerencial_pct
  FROM printiag_metas_maquinas m
  JOIN printiag_maquinas q ON q.nome_norm = norm(m.nome_maquina)
  WHERE p_maquinas IS NULL OR q.id = ANY(p_maquinas);
$$;

-- =========================================================
-- 4. printag_get_metas_maquinas
-- Listagem para a tela de Metas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_get_metas_maquinas();

CREATE OR REPLACE FUNCTION printag_get_metas_maquinas()
RETURNS TABLE (
  nome_maquina                   TEXT,
  meta_velocidade_virando        NUMERIC,
  meta_velocidade_com_acerto     NUMERIC,
  meta_tempo_medio_acerto        NUMERIC,
  meta_improdutivo_area_pct      NUMERIC,
  meta_improdutivo_gerencial_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT
    m.nome_maquina,
    m.meta_velocidade_virando,
    m.meta_velocidade_com_acerto,
    m.meta_tempo_medio_acerto,
    ROUND((m.meta_indisponibilidade_virando_area      * 100)::NUMERIC, 2),
    ROUND((m.meta_indisponibilidade_virando_gerencial * 100)::NUMERIC, 2)
  FROM printiag_metas_maquinas m
  ORDER BY m.nome_maquina;
END;
$$;

-- =========================================================
-- 5. printag_update_metas_maquina
-- Grava as metas de uma máquina. Parâmetros tipados, sem SQL dinâmico.
-- Alterar meta_indisponibilidade_virando_area também afeta
-- meta_horas_imp_area na mv_base_apontamentos no próximo REFRESH.
-- =========================================================
DROP FUNCTION IF EXISTS printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION printag_update_metas_maquina(
  p_nome_maquina                   TEXT,
  p_meta_velocidade_virando        NUMERIC,
  p_meta_velocidade_com_acerto     NUMERIC,
  p_meta_tempo_medio_acerto        NUMERIC,
  p_meta_improdutivo_area_pct      NUMERIC DEFAULT NULL,
  p_meta_improdutivo_gerencial_pct NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem editar as metas.';
  END IF;

  IF p_meta_velocidade_virando    < 0 THEN p_meta_velocidade_virando    := NULL; END IF;
  IF p_meta_velocidade_com_acerto < 0 THEN p_meta_velocidade_com_acerto := NULL; END IF;
  IF p_meta_tempo_medio_acerto    < 0 THEN p_meta_tempo_medio_acerto    := NULL; END IF;
  IF p_meta_improdutivo_area_pct < 0 OR p_meta_improdutivo_area_pct > 100 THEN
    p_meta_improdutivo_area_pct := NULL;
  END IF;
  IF p_meta_improdutivo_gerencial_pct < 0 OR p_meta_improdutivo_gerencial_pct > 100 THEN
    p_meta_improdutivo_gerencial_pct := NULL;
  END IF;

  UPDATE printiag_metas_maquinas
  SET meta_velocidade_virando                  = p_meta_velocidade_virando,
      meta_velocidade_com_acerto               = p_meta_velocidade_com_acerto,
      meta_tempo_medio_acerto                  = p_meta_tempo_medio_acerto,
      meta_indisponibilidade_virando_area      = p_meta_improdutivo_area_pct / 100.0,
      meta_indisponibilidade_virando_gerencial = p_meta_improdutivo_gerencial_pct / 100.0
  WHERE nome_maquina = p_nome_maquina;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Máquina "%" não encontrada em printiag_metas_maquinas.', p_nome_maquina;
  END IF;
END;
$$;

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_ind_improdutivos_semana(INT, INT[], INT[], TEXT[], TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_improdutivos_mes(INT, INT[], INT[], TEXT[], TEXT[])   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_metas_fixas(INT[])   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_get_metas_maquinas() TO authenticated;
GRANT EXECUTE ON FUNCTION printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC);
-- DROP FUNCTION IF EXISTS printag_get_metas_maquinas();
-- DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);
-- DROP FUNCTION IF EXISTS printag_indm_improdutivos_mes(INT, INT[], INT[], TEXT[], TEXT[]);
-- DROP FUNCTION IF EXISTS printag_ind_improdutivos_semana(INT, INT[], INT[], TEXT[], TEXT[]);
-- -- reexecutar os blocos correspondentes de 011, 014 e 019
-- NOTIFY pgrst, 'reload schema';

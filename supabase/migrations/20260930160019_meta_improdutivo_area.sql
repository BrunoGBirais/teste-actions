-- =========================================================
-- PrintAG — 019: meta de improdutivo área nos gráficos
--
-- O gráfico "Improdutivos Área" passou a exibir percentual
-- (área / (virando + área)) e a linha dourada vira uma reta ligada a
-- meta_indisponibilidade_virando_area, que já existia em
-- printiag_metas_maquinas mas não era editável nem exposta ao frontend.
--
-- A coluna é uma fração 0-1 no banco; as RPCs devolvem e recebem em %
-- para casar com o que o usuário digita na tela de Metas.
--
-- Como o RETURNS TABLE muda, as três funções da migration 018 precisam
-- de DROP antes do CREATE.
-- =========================================================

-- =======  UP  ========

-- =========================================================
-- 1. printag_metas_fixas
-- Metas agregadas por média simples das máquinas selecionadas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);

CREATE OR REPLACE FUNCTION printag_metas_fixas(
  p_maquinas INT[] DEFAULT NULL
)
RETURNS TABLE (
  meta_velocidade_virando    NUMERIC,
  meta_velocidade_com_acerto NUMERIC,
  meta_tempo_medio_acerto    NUMERIC,
  meta_improdutivo_area_pct  NUMERIC
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
    ROUND((AVG(m.meta_indisponibilidade_virando_area) * 100)::NUMERIC, 2) AS meta_improdutivo_area_pct
  FROM printiag_metas_maquinas m
  JOIN printiag_maquinas q ON q.nome_norm = norm(m.nome_maquina)
  WHERE p_maquinas IS NULL OR q.id = ANY(p_maquinas);
$$;

-- =========================================================
-- 2. printag_get_metas_maquinas
-- Listagem para a tela de Metas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_get_metas_maquinas();

CREATE OR REPLACE FUNCTION printag_get_metas_maquinas()
RETURNS TABLE (
  nome_maquina               TEXT,
  meta_velocidade_virando    NUMERIC,
  meta_velocidade_com_acerto NUMERIC,
  meta_tempo_medio_acerto    NUMERIC,
  meta_improdutivo_area_pct  NUMERIC
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
    ROUND((m.meta_indisponibilidade_virando_area * 100)::NUMERIC, 2)
  FROM printiag_metas_maquinas m
  ORDER BY m.nome_maquina;
END;
$$;

-- =========================================================
-- 3. printag_update_metas_maquina
-- Grava as metas de uma máquina. Parâmetros tipados, sem SQL dinâmico.
-- Alterar meta_indisponibilidade_virando_area também afeta
-- meta_horas_imp_area na mv_base_apontamentos no próximo REFRESH.
-- =========================================================
DROP FUNCTION IF EXISTS printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION printag_update_metas_maquina(
  p_nome_maquina               TEXT,
  p_meta_velocidade_virando    NUMERIC,
  p_meta_velocidade_com_acerto NUMERIC,
  p_meta_tempo_medio_acerto    NUMERIC,
  p_meta_improdutivo_area_pct  NUMERIC DEFAULT NULL
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

  UPDATE printiag_metas_maquinas
  SET meta_velocidade_virando              = p_meta_velocidade_virando,
      meta_velocidade_com_acerto           = p_meta_velocidade_com_acerto,
      meta_tempo_medio_acerto              = p_meta_tempo_medio_acerto,
      meta_indisponibilidade_virando_area  = p_meta_improdutivo_area_pct / 100.0
  WHERE nome_maquina = p_nome_maquina;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Máquina "%" não encontrada em printiag_metas_maquinas.', p_nome_maquina;
  END IF;
END;
$$;

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_metas_fixas(INT[])   TO authenticated;
GRANT EXECUTE ON FUNCTION printag_get_metas_maquinas() TO authenticated;
GRANT EXECUTE ON FUNCTION printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC);
-- DROP FUNCTION IF EXISTS printag_get_metas_maquinas();
-- DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);
-- -- reexecutar os blocos correspondentes de 018_metas_fixas_graficos.sql
-- NOTIFY pgrst, 'reload schema';

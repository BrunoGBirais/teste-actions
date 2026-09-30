-- =========================================================
-- PrintAG — 018: metas fixas por equipamento para os gráficos
--
-- As linhas pontilhadas dos gráficos de indicadores eram derivadas
-- do mix real de cada período, então oscilavam ao longo do ano.
-- Passam a ser um valor fixo cadastrado por máquina em
-- printiag_metas_maquinas, agregado por média simples quando mais
-- de uma máquina está no filtro.
--
-- Gráficos afetados (semanal e mensal):
--   Velocidade Média Virando   -> meta_velocidade_virando (já existia)
--   Velocidade + Acerto        -> meta_velocidade_com_acerto (nova)
--   Tempo Médio de Acerto      -> meta_tempo_medio_acerto (nova, em minutos)
-- =========================================================

-- =======  UP  ========

ALTER TABLE printiag_metas_maquinas
  ADD COLUMN IF NOT EXISTS meta_velocidade_com_acerto NUMERIC,
  ADD COLUMN IF NOT EXISTS meta_tempo_medio_acerto    NUMERIC;

COMMENT ON COLUMN printiag_metas_maquinas.meta_velocidade_com_acerto IS
  'Meta fixa de peças/hora considerando virando + acerto + improdutivos área e gerenciais.';
COMMENT ON COLUMN printiag_metas_maquinas.meta_tempo_medio_acerto IS
  'Meta fixa de minutos por acerto.';

-- Valor inicial do tempo de acerto: média das metas de mesma faca e troca de
-- faca, convertida para minutos. Ajustável na tela de Metas.
UPDATE printiag_metas_maquinas
SET meta_tempo_medio_acerto = ROUND(
      ((COALESCE(meta_acerto_mesma_faca, 0) + COALESCE(meta_acerto_troca_faca, 0)) / 2 * 60)::NUMERIC, 1)
WHERE meta_tempo_medio_acerto IS NULL
  AND (meta_acerto_mesma_faca IS NOT NULL OR meta_acerto_troca_faca IS NOT NULL);

-- =========================================================
-- 1. printag_metas_fixas
-- Metas agregadas por média simples das máquinas selecionadas.
-- Colunas sem valor cadastrado voltam NULL e o frontend omite a linha.
-- =========================================================
-- Drop necessario: migrations 019/020/026 alteram o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);

CREATE OR REPLACE FUNCTION printag_metas_fixas(
  p_maquinas INT[] DEFAULT NULL
)
RETURNS TABLE (
  meta_velocidade_virando    NUMERIC,
  meta_velocidade_com_acerto NUMERIC,
  meta_tempo_medio_acerto    NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ROUND(AVG(m.meta_velocidade_virando)::NUMERIC,    2) AS meta_velocidade_virando,
    ROUND(AVG(m.meta_velocidade_com_acerto)::NUMERIC, 2) AS meta_velocidade_com_acerto,
    ROUND(AVG(m.meta_tempo_medio_acerto)::NUMERIC,    2) AS meta_tempo_medio_acerto
  FROM printiag_metas_maquinas m
  JOIN printiag_maquinas q ON q.nome_norm = norm(m.nome_maquina)
  WHERE p_maquinas IS NULL OR q.id = ANY(p_maquinas);
$$;

-- =========================================================
-- 2. printag_get_metas_maquinas
-- Listagem para a tela de Metas.
-- =========================================================
-- Drop necessario: migrations 019/020 alteram o tipo de retorno desta funcao.
DROP FUNCTION IF EXISTS printag_get_metas_maquinas();

CREATE OR REPLACE FUNCTION printag_get_metas_maquinas()
RETURNS TABLE (
  nome_maquina               TEXT,
  meta_velocidade_virando    NUMERIC,
  meta_velocidade_com_acerto NUMERIC,
  meta_tempo_medio_acerto    NUMERIC
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
    m.meta_tempo_medio_acerto
  FROM printiag_metas_maquinas m
  ORDER BY m.nome_maquina;
END;
$$;

-- =========================================================
-- 3. printag_update_metas_maquina
-- Grava as três metas de uma máquina. Parâmetros tipados, sem SQL
-- dinâmico: o nome da coluna nunca vem do cliente.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_update_metas_maquina(
  p_nome_maquina               TEXT,
  p_meta_velocidade_virando    NUMERIC,
  p_meta_velocidade_com_acerto NUMERIC,
  p_meta_tempo_medio_acerto    NUMERIC
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

  UPDATE printiag_metas_maquinas
  SET meta_velocidade_virando    = p_meta_velocidade_virando,
      meta_velocidade_com_acerto = p_meta_velocidade_com_acerto,
      meta_tempo_medio_acerto    = p_meta_tempo_medio_acerto
  WHERE nome_maquina = p_nome_maquina;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Máquina "%" não encontrada em printiag_metas_maquinas.', p_nome_maquina;
  END IF;
END;
$$;

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
GRANT EXECUTE ON FUNCTION printag_metas_fixas(INT[])                                  TO authenticated;
GRANT EXECUTE ON FUNCTION printag_get_metas_maquinas()                                TO authenticated;
GRANT EXECUTE ON FUNCTION printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS printag_update_metas_maquina(TEXT, NUMERIC, NUMERIC, NUMERIC);
-- DROP FUNCTION IF EXISTS printag_get_metas_maquinas();
-- DROP FUNCTION IF EXISTS printag_metas_fixas(INT[]);
-- ALTER TABLE printiag_metas_maquinas
--   DROP COLUMN IF EXISTS meta_velocidade_com_acerto,
--   DROP COLUMN IF EXISTS meta_tempo_medio_acerto;
-- NOTIFY pgrst, 'reload schema';

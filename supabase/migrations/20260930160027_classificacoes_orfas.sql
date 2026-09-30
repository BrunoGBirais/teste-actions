-- =====================================================================
-- 027_classificacoes_orfas.sql
--
-- O join da MV com printiag_classificacao é LEFT (010 L64-71): apontamento
-- cujo par (tipo_apontam, motivo) não está cadastrado entra com
-- classificacao_perda nula, não cai em nenhum balde de hora e some dos
-- indicadores — sem erro, sem aviso.
--
-- Hoje só dava para achar esses casos rodando SQL na mão. Esta RPC alimenta
-- a sub-aba "Órfãs" da tela de Classificações, para que quem conhece a
-- operação faça o de-para pela interface.
--
-- Lê printag_apontamentos, não a MV: assim um órfão de upload recente
-- aparece antes do próximo printag_refresh_base().
-- =====================================================================

-- =======  UP  ========

-- =========================================================
-- printag_get_classificacoes_orfas
-- Pares (tipo_apontam, motivo) sem correspondência em printiag_classificacao.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_get_classificacoes_orfas()
RETURNS TABLE (
  tipo_apontam     TEXT,
  motivo           TEXT,
  areas            TEXT,
  maquinas         TEXT,
  qtd_apontamentos BIGINT,
  horas            NUMERIC
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
    a.tipo_apontam,
    COALESCE(a.motivo, '')                                          AS motivo,
    -- LEFT JOIN: máquina fora de printiag_maquinas não tem área.
    COALESCE(string_agg(DISTINCT m.area, ', '), '(não cadastrada)')  AS areas,
    string_agg(DISTINCT a.equipamento, ', ')                        AS maquinas,
    count(*)                                                        AS qtd_apontamentos,
    -- Mesma fórmula de tempo_total na MV (010 L32).
    ROUND(
      SUM(EXTRACT(EPOCH FROM (a.fim - a.inicio)) / 3600.0)::NUMERIC, 1
    )                                                               AS horas
  FROM printag_apontamentos a
  LEFT JOIN printiag_maquinas m ON m.nome_norm = norm(a.equipamento)
  WHERE NOT EXISTS (
    SELECT 1 FROM printiag_classificacao c
    WHERE c.chave_norm = a.chave
  )
  GROUP BY a.tipo_apontam, COALESCE(a.motivo, '')
  ORDER BY 6 DESC NULLS LAST, 5 DESC;
END;
$$;

-- ---- Permissões ----
-- Leitura exige só is_member, como printag_get_classificacoes. Cadastrar
-- a órfã passa por printag_insert_classificacao, que exige admin.
GRANT EXECUTE ON FUNCTION printag_get_classificacoes_orfas() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Conferência — o total deve bater com o buraco visto na MV:
--   SELECT sum(qtd_apontamentos) FROM printag_get_classificacoes_orfas();
--   SELECT count(*) FROM mv_base_apontamentos
--   WHERE maquina_id IS NOT NULL AND classificacao_perda IS NULL;
--
-- (a segunda pode vir menor: ela ignora apontamento de máquina que não
--  está em printiag_maquinas, a primeira não.)
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS printag_get_classificacoes_orfas();

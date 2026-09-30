-- =====================================================================
-- 028_filtros_com_area.sql
--
-- O dashboard vai passar a aceitar várias máquinas por vez, travadas numa
-- mesma área (misturar Impressão com Acabamento somaria realizados de
-- processos distintos contra uma meta só). Para o front impor essa trava
-- ele precisa saber a área de cada máquina, e hoje printag_ind_filtros /
-- printag_indm_filtros devolvem só {id, nome}.
--
-- A coluna area já existe na mv_base_apontamentos (010 L48); aqui só a
-- expomos no JSON. Também é dela que sai o default do filtro, que passa a
-- ser "todas as de Acabamento" em vez de todas as máquinas.
--
-- RETURNS TABLE não muda — maquinas continua sendo JSON, só o conteúdo do
-- JSON ganha uma chave. Por isso CREATE OR REPLACE basta, sem DROP.
-- =====================================================================

-- =======  UP  ========

-- =========================================================
-- 1. printag_ind_filtros (semanal)
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
    (SELECT json_agg(r ORDER BY r.area, r.nome)
     FROM (
       SELECT DISTINCT maquina_id AS id, nome_maquina AS nome, area
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

-- =========================================================
-- 2. printag_indm_filtros (mensal)
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
    (SELECT json_agg(r ORDER BY r.area, r.nome)
     FROM (
       SELECT DISTINCT maquina_id AS id, nome_maquina AS nome, area
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

-- ---- Permissões ----
GRANT EXECUTE ON FUNCTION printag_ind_filtros(INT)  TO authenticated;
GRANT EXECUTE ON FUNCTION printag_indm_filtros(INT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Conferência — cada item de maquinas agora tem id, nome e area:
--   SELECT maquinas FROM printag_ind_filtros(2026);
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- Reaplicar as versões de 011 (printag_ind_filtros) e 014
-- (printag_indm_filtros), que montam maquinas sem a coluna area.

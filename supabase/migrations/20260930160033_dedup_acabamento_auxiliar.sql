-- =====================================================================
-- 033_dedup_acabamento_auxiliar.sql
--
-- Sintoma (upload do snapshot):
--   ❌ Falha ao atualizar a base analítica: duplicate key value violates
--      unique constraint "mv_base_apontamentos_id_idx"
--
-- Causa: a MV faz
--   LEFT JOIN printiag_acabamento_auxiliar aa
--          ON norm(aa.descricao) = norm(ac.raw_tipo_acabamento)
-- mas a tabela só tem PRIMARY KEY em `descricao` (raw), não em
-- norm(descricao). O seed traz 'Colagem Fundo Automático' E
-- 'Colagem Fundo Automatico' — duas descrições distintas que colapsam
-- no mesmo norm() ('colagem fundo automatico'). O LEFT JOIN devolve
-- então 2 linhas para cada apontamento cuja OS tem esse acabamento, o
-- `id` do apontamento se repete na MV e o índice único (id) estoura no
-- REFRESH ... CONCURRENTLY.
--
-- É a mesma armadilha que printiag_classificacao já contorna com
-- LATERAL + LIMIT 1 (ver 008_schema_base.sql).
--
-- Correção: colapsar as descrições que já normalizam igual e criar um
-- índice único em norm(descricao) — norm() é IMMUTABLE, então pode ser
-- indexada — para que nenhum seed futuro reintroduza o fan-out.
--
-- Depois de aplicar, rodar um refresh (botão "Atualizar" do dashboard ou
-- SELECT printag_refresh_base();) para repovoar a MV.
-- =====================================================================

-- =======  UP  ========

-- 0. norm() chama unaccent() sem schema. No Postgres 17+, CREATE INDEX avalia
--    funções com search_path restrito (pg_catalog, pg_temp), e o unaccent some.
--    Fixar o search_path da função resolve (Supabase: extensão em public ou extensions).
ALTER FUNCTION norm(TEXT) SET search_path = public, extensions, pg_catalog;

-- 1. Mantém a primeira descrição de cada grupo normalizado.
--    As duplicatas conhecidas apontam para o mesmo `acabamento`, então
--    nenhuma classificação muda; some apenas a linha redundante.
WITH ranked AS (
  SELECT descricao,
         ROW_NUMBER() OVER (PARTITION BY norm(descricao) ORDER BY descricao) AS rn
  FROM printiag_acabamento_auxiliar
)
DELETE FROM printiag_acabamento_auxiliar aa
USING ranked r
WHERE r.descricao = aa.descricao
  AND r.rn > 1;

-- 2. Trava: a MV depende de no máximo 1 linha por norm(descricao).
CREATE UNIQUE INDEX IF NOT EXISTS uq_paux_descricao_norm
  ON printiag_acabamento_auxiliar (norm(descricao));

-- =======  DOWN  ========
-- DROP INDEX IF EXISTS uq_paux_descricao_norm;
-- (as linhas removidas eram redundantes; não há o que restaurar)

-- =====================================================================
-- 022_dedup_classificacao.sql
--
-- O seed de 008 veio do Excel com variantes de grafia da mesma chave
-- ('OciosoRefeicao' e 'OciosoRefeição', 'OciosoManutencao Preventiva' e
-- 'OciosoManutenção Preventiva', ...). Como o UNIQUE original é sobre
-- `chave` (raw) e não sobre `chave_norm`, todas coexistem.
--
-- Na prática só uma delas tem efeito: a MV faz
--   LEFT JOIN LATERAL (... WHERE chave_norm = a.chave ORDER BY id LIMIT 1)
-- ou seja, vence sempre a de menor id. As demais são linhas mortas que
-- só poluem a tela de administração.
--
-- Esta migration:
--   1. Reporta grupos em que as variantes DISCORDAM na classificação
--      (nenhum caso conhecido hoje, mas precisa ser visto se aparecer).
--   2. Remove as variantes perdedoras, mantendo a de menor id — ou seja,
--      exatamente a que a MV já usava. Nenhum indicador muda de valor.
--   3. Cria UNIQUE sobre chave_norm para o problema não voltar.
--
-- Dependência: aplicar depois de 021.
-- =====================================================================

-- =======  UP  ========

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Diagnóstico: variantes que normalizam igual mas classificam diferente.
--    Só emite aviso; a resolução continua sendo "menor id vence".
-- ---------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT chave_norm,
           string_agg(DISTINCT chave, ' | ' ORDER BY chave)               AS variantes,
           count(DISTINCT classificacao_perda || '/' || atuacao ||
                          '/' || COALESCE(nivel_atuacao, ''))             AS distintas
    FROM printiag_classificacao
    GROUP BY chave_norm
    HAVING count(*) > 1
  LOOP
    IF r.distintas > 1 THEN
      RAISE WARNING
        'Conflito em "%": as variantes (%) tinham classificações diferentes. Mantida a de menor id — revise na tela de Classificações.',
        r.chave_norm, r.variantes;
    ELSE
      RAISE NOTICE 'Removendo duplicatas equivalentes de "%": %', r.chave_norm, r.variantes;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. Remove as perdedoras. `a.id > b.id` mantém a de menor id do grupo,
--    que é a mesma que o ORDER BY id LIMIT 1 da MV já elegia.
-- ---------------------------------------------------------------------
DELETE FROM printiag_classificacao a
USING printiag_classificacao b
WHERE a.chave_norm = b.chave_norm
  AND a.id > b.id;

-- ---------------------------------------------------------------------
-- 3. Impede o retorno do problema.
--    O índice simples vira redundante: o UNIQUE já cria o seu próprio.
--    Postgres não tem ADD CONSTRAINT IF NOT EXISTS — daí o DO.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_pclass_chave_norm'
      AND conrelid = 'printiag_classificacao'::regclass
  ) THEN
    ALTER TABLE printiag_classificacao
      ADD CONSTRAINT uq_pclass_chave_norm UNIQUE (chave_norm);
  ELSE
    RAISE NOTICE 'uq_pclass_chave_norm já existe — nada a fazer.';
  END IF;
END $$;

DROP INDEX IF EXISTS idx_pclass_chave_norm;

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência (deve retornar zero linhas):
--   SELECT chave_norm, count(*) FROM printiag_classificacao
--   GROUP BY chave_norm HAVING count(*) > 1;
--
-- A MV não precisa de REFRESH: as linhas removidas nunca foram usadas.
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- Não há como restaurar as linhas removidas sem o seed original de 008.
-- Para apenas soltar a restrição:
--
-- ALTER TABLE printiag_classificacao DROP CONSTRAINT IF EXISTS uq_pclass_chave_norm;
-- CREATE INDEX IF NOT EXISTS idx_pclass_chave_norm ON printiag_classificacao (chave_norm);

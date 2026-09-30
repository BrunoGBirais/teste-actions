-- =====================================================================
-- 026_metas_outras_maquinas.sql
--
-- printag_get_metas_maquinas faz SELECT direto de printiag_metas_maquinas,
-- e printag_update_metas_maquina é um UPDATE. Ou seja: máquina sem linha
-- aqui não aparece na tela de Metas e não tem como ser preenchida pela UI.
--
-- Esta migration cria as 7 linhas que faltavam para as máquinas passarem
-- a existir na tela.
--
-- ⚠️ OS VALORES ABAIXO SÃO PROVISÓRIOS, NÃO VIERAM DE LEVANTAMENTO.
--    São chute derivado da velocidade limite de 024 (~55% dela, que é a
--    proporção observada nas coladeiras) e das metas de improdutivo das
--    coladeiras. Servem só para a tela não abrir vazia. Ajuste na UI antes
--    de qualquer um desses números virar indicador oficial.
--
-- ⚠️ ATENÇÃO AO NOME: o join da MV em 010 L275 é
--       meta.nome_maquina = wf.nome_maquina
--    SEM norm(), diferente de todos os outros joins do projeto. O nome
--    precisa bater caractere a caractere com printiag_maquinas.nome_maquina
--    definido em 024. Por isso os nomes abaixo são cópia literal de lá.
--
-- Dependência: aplicar depois de 018, 019, 020 e 024. A seção 2 reescreve
-- printag_metas_fixas em cima da versão de 020 — aplicar fora de ordem
-- faria o dashboard perder meta_improdutivo_gerencial_pct.
-- =====================================================================

-- =======  UP  ========

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Cria as linhas. DO NOTHING de propósito: se a máquina já tiver meta
--    cadastrada, o chute não sobrescreve.
--
--    meta_tempo_medio_acerto é redundante com as duas metas de faca —
--    mantive a identidade (mesma+troca)/2*60 que 018 L31 usou no backfill,
--    senão a tela mostra número que não fecha com ele mesmo.
-- ---------------------------------------------------------------------
INSERT INTO printiag_metas_maquinas
  (nome_maquina,
   meta_velocidade_virando,
   meta_velocidade_com_acerto,
   meta_tempo_medio_acerto,
   meta_indisponibilidade_virando_gerencial,
   meta_indisponibilidade_virando_area,
   meta_acerto_mesma_faca,
   meta_acerto_troca_faca)
VALUES
  ('BOBST01',                     4400,  3500, 21.0, 0.16, 0.09, 0.10, 0.60),
  ('BOBST02',                     4400,  3500, 21.0, 0.16, 0.09, 0.10, 0.60),
  ('Cortadeira CPR-1200',         5500,  4400, 15.0, 0.16, 0.09, 0.10, 0.40),
  ('Heidelberg Speedmaster',      8250,  6600, 30.0, 0.16, 0.09, 0.15, 0.85),
  ('Komori LSX 529',              8250,  6600, 30.0, 0.16, 0.09, 0.15, 0.85),
  ('Suprema Hotstamping 1040 01',  550,   440, 36.0, 0.16, 0.09, 0.20, 1.00),
  ('Suprema Hotstamping 1040 02',  550,   440, 36.0, 0.16, 0.09, 0.20, 1.00)
ON CONFLICT (nome_maquina) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Blinda a meta agregada do dashboard.
--
--    printag_metas_fixas(NULL) é o que o dashboard chama quando o filtro
--    está em "todas as máquinas", e ela fazia AVG sobre a tabela inteira.
--    Isso funcionava porque só existiam as 3 coladeiras. Com a seção 1
--    inserindo a Komori (8.250) ao lado da Expertfold (48.122), a média
--    vira um número sem significado e as linhas de meta dos gráficos de
--    Acabamento saem do lugar. Sem esta seção, a seção 1 quebra o
--    dashboard.
--
--    A correção restringe o agregado à área Acabamento, o que devolve
--    exatamente os valores de antes da seção 1. Quando o dashboard cobrir
--    outras áreas,
--    esta função vai precisar receber a área como parâmetro.
--
--    Base: a versão de 020, com 5 colunas. CREATE OR REPLACE não altera
--    RETURNS TABLE, daí o DROP.
-- ---------------------------------------------------------------------
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
  WHERE (p_maquinas IS NULL OR q.id = ANY(p_maquinas))
    AND (p_maquinas IS NOT NULL OR q.area = 'Acabamento');
$$;

-- ---- Permissões ----
GRANT EXECUTE ON FUNCTION printag_metas_fixas(INT[]) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Unidades, para preencher na tela de Metas:
--   meta_velocidade_virando    peças/hora   (ex.: 48122.41596)
--   meta_improdutivo_area_pct  percentual   (a UI grava /100 na coluna)
--   meta_tempo_medio_acerto    minutos      (a UI converte)
--   meta_acerto_mesma_faca     horas        (ex.: 0.09 = 5,4 min)
--   meta_acerto_troca_faca     horas        (ex.: 0.55 = 33 min)
--
-- Conferência — o agregado do Acabamento não pode ter mudado:
--   SELECT * FROM printag_metas_fixas(NULL);
--   -- 5 colunas; meta_velocidade_virando ≈ 23509.69,
--   -- meta_improdutivo_area_pct ≈ 8.43, meta_improdutivo_gerencial_pct ≈ 16.55
--
-- E as 10 máquinas devem aparecer na tela:
--   SELECT * FROM printag_get_metas_maquinas();
--
-- Nenhuma máquina pode ficar sem par (o join da MV é sem norm):
--   SELECT m.nome_maquina FROM printiag_metas_maquinas m
--   LEFT JOIN printiag_maquinas q ON q.nome_maquina = m.nome_maquina
--   WHERE q.id IS NULL;
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- DELETE FROM printiag_metas_maquinas WHERE nome_maquina IN (
--   'BOBST01', 'BOBST02', 'Cortadeira CPR-1200', 'Heidelberg Speedmaster',
--   'Komori LSX 529', 'Suprema Hotstamping 1040 01',
--   'Suprema Hotstamping 1040 02');
-- -- e reaplicar a versão de printag_metas_fixas da 020.

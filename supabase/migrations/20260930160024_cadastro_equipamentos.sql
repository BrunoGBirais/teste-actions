-- =====================================================================
-- 024_cadastro_equipamentos.sql
--
-- Duas tabelas guardam cadastro de máquina e elas divergiram:
--
--   aux_equipamento     (OEE legado, PK = nome)  → tinha só 5 linhas, com
--                        nomes curtos ('AMBITION') e faltando 5 máquinas.
--   printiag_maquinas   (schema novo, PK = id)   → tinha só as 3 coladeiras.
--
-- A 012 já havia padronizado printiag_maquinas para o nome completo usado
-- no CSV ('Coladeira Ambition'), mas aux_equipamento ficou para trás. Como
-- norm('AMBITION') ≠ norm('Coladeira Ambition'), qualquer join entre as
-- duas falha silenciosamente.
--
-- Esta migration usa a planilha "Velocidade Limite" como fonte da verdade
-- e deixa as duas tabelas com as mesmas 10 máquinas e os mesmos nomes.
--
-- ⚠️ Efeito colateral esperado: a velocidade limite da Expertfold em
--    aux_equipamento passa de 75.000 para 80.000 (valor da planilha, que já
--    era o de printiag_maquinas). Se os 75.000 forem propositais, remova a
--    linha correspondente da seção 2 antes de aplicar.
--
-- Nenhum indicador do dashboard muda: os gráficos de Acabamento leem
-- printiag_metas_maquinas, não estas tabelas. Adicionar máquinas novas
-- também não polui os filtros — eles vêm de DISTINCT sobre a MV, ou seja,
-- só aparece máquina que tem apontamento.
-- =====================================================================

-- =======  UP  ========

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Renomeia as referências antigas em aux_meta_equipamento.
--    Precisa vir ANTES do delete da seção 3 (não há FK, mas as linhas
--    ficariam órfãs pelo nome).
-- ---------------------------------------------------------------------
-- Se o nome novo já existe para o mesmo ano (migration já aplicada), a linha
-- antiga é descartada — renomeá-la violaria a PK (equipamento, ano).
WITH renomear(antigo, novo) AS (
  VALUES ('AMBITION',   'Coladeira Ambition'),
         ('EXPERTFOLD', 'Coladeira Expertfold'),
         ('NOVAFOLD',   'Coladeira Novafold')
)
DELETE FROM aux_meta_equipamento a
  USING renomear r
  WHERE upper(a.equipamento) = r.antigo
    AND EXISTS (
      SELECT 1 FROM aux_meta_equipamento b
        WHERE b.equipamento = r.novo AND b.ano = a.ano
    );

WITH renomear(antigo, novo) AS (
  VALUES ('AMBITION',   'Coladeira Ambition'),
         ('EXPERTFOLD', 'Coladeira Expertfold'),
         ('NOVAFOLD',   'Coladeira Novafold')
)
UPDATE aux_meta_equipamento a
  SET equipamento = r.novo
  FROM renomear r
  WHERE upper(a.equipamento) = r.antigo;

-- ---------------------------------------------------------------------
-- 2. Cadastro completo em aux_equipamento (planilha "Velocidade Limite").
-- ---------------------------------------------------------------------
INSERT INTO aux_equipamento (equipamento, area, velocidade_limite) VALUES
  ('BOBST01',                     'Corte e Vinco',   8000),
  ('BOBST02',                     'Corte e Vinco',   8000),
  ('Coladeira Ambition',          'Acabamento',     25000),
  ('Coladeira Expertfold',        'Acabamento',     80000),
  ('Coladeira Novafold',          'Acabamento',     25000),
  ('Cortadeira CPR-1200',         'Corte de Papel', 10000),
  ('Heidelberg Speedmaster',      'Impressão',      15000),
  ('Komori LSX 529',              'Impressão',      15000),
  ('Suprema Hotstamping 1040 01', 'Hot Stamping',    1000),
  ('Suprema Hotstamping 1040 02', 'Hot Stamping',    1000)
ON CONFLICT (equipamento) DO UPDATE
  SET area              = EXCLUDED.area,
      velocidade_limite = EXCLUDED.velocidade_limite;

-- ---------------------------------------------------------------------
-- 3. Remove os nomes curtos, agora substituídos pelos completos.
-- ---------------------------------------------------------------------
DELETE FROM aux_equipamento
  WHERE equipamento IN ('AMBITION', 'EXPERTFOLD', 'NOVAFOLD');

-- ---------------------------------------------------------------------
-- 4. Mesmo cadastro em printiag_maquinas.
--    O conflito é por nome_norm (coluna gerada), não pelo nome cru.
-- ---------------------------------------------------------------------
INSERT INTO printiag_maquinas (nome_maquina, area, velocidade) VALUES
  ('BOBST01',                     'Corte e Vinco',   8000),
  ('BOBST02',                     'Corte e Vinco',   8000),
  ('Coladeira Ambition',          'Acabamento',     25000),
  ('Coladeira Expertfold',        'Acabamento',     80000),
  ('Coladeira Novafold',          'Acabamento',     25000),
  ('Cortadeira CPR-1200',         'Corte de Papel', 10000),
  ('Heidelberg Speedmaster',      'Impressão',      15000),
  ('Komori LSX 529',              'Impressão',      15000),
  ('Suprema Hotstamping 1040 01', 'Hot Stamping',    1000),
  ('Suprema Hotstamping 1040 02', 'Hot Stamping',    1000)
ON CONFLICT (nome_norm) DO UPDATE
  SET nome_maquina = EXCLUDED.nome_maquina,
      area         = EXCLUDED.area,
      velocidade   = EXCLUDED.velocidade;

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência — as duas devem retornar as mesmas 10 máquinas:
--   SELECT equipamento, area, velocidade_limite FROM aux_equipamento
--   ORDER BY area, equipamento;
--   SELECT id, nome_maquina, area, velocidade FROM printiag_maquinas
--   ORDER BY area, nome_maquina;
--
-- E nenhum nome deve ficar sem par:
--   SELECT e.equipamento FROM aux_equipamento e
--   LEFT JOIN printiag_maquinas q ON q.nome_norm = norm(e.equipamento)
--   WHERE q.id IS NULL;
--
-- A MV não precisa de REFRESH: os IDs das 3 coladeiras não mudaram.
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- DELETE FROM aux_equipamento WHERE equipamento IN (
--   'Cortadeira CPR-1200', 'Heidelberg Speedmaster', 'Komori LSX 529',
--   'Suprema Hotstamping 1040 01', 'Suprema Hotstamping 1040 02');
-- DELETE FROM printiag_maquinas WHERE nome_norm IN (
--   norm('BOBST01'), norm('BOBST02'), norm('Cortadeira CPR-1200'),
--   norm('Heidelberg Speedmaster'), norm('Komori LSX 529'),
--   norm('Suprema Hotstamping 1040 01'), norm('Suprema Hotstamping 1040 02'));

-- =========================================================
-- PrintAG — 012: Corrige nomes de máquinas no banco existente
--
-- Problema: printiag_maquinas tinha nomes curtos (AMBITION etc.)
-- mas o CSV usa 'Coladeira Ambition' etc.
-- norm('Coladeira Ambition') ≠ norm('AMBITION') → JOIN falha
-- → nome_maquina = NULL → metas sempre NULL/0 no dashboard.
-- =========================================================

-- 1. Renomeia entradas em printiag_maquinas
UPDATE printiag_maquinas SET nome_maquina = 'Coladeira Ambition'
  WHERE lower(nome_maquina) = 'ambition';

UPDATE printiag_maquinas SET nome_maquina = 'Coladeira Expertfold'
  WHERE lower(nome_maquina) = 'expertfold';

UPDATE printiag_maquinas SET nome_maquina = 'Coladeira Novafold'
  WHERE lower(nome_maquina) = 'novafold';

-- Garante inserção caso a tabela estivesse vazia
INSERT INTO printiag_maquinas (nome_maquina, area, velocidade) VALUES
  ('Coladeira Novafold',   'Acabamento', 25000),
  ('Coladeira Ambition',   'Acabamento', 25000),
  ('Coladeira Expertfold', 'Acabamento', 80000)
ON CONFLICT (nome_norm) DO UPDATE
  SET area       = EXCLUDED.area,
      velocidade = EXCLUDED.velocidade;

-- 2. Atualiza printiag_metas_maquinas
DELETE FROM printiag_metas_maquinas
  WHERE nome_maquina IN ('AMBITION', 'EXPERTFOLD', 'NOVAFOLD');

INSERT INTO printiag_metas_maquinas
  (nome_maquina,
   meta_velocidade_virando,
   meta_indisponibilidade_virando_gerencial,
   meta_indisponibilidade_virando_area,
   meta_acerto_mesma_faca,
   meta_acerto_troca_faca)
VALUES
  ('Coladeira Ambition',   10087.68452, 0.1875, 0.0825, 0.08, 0.62),
  ('Coladeira Expertfold', 48122.41596, 0.1583, 0.1033, 0.09, 0.55),
  ('Coladeira Novafold',   12318.97392, 0.1508, 0.0670, 0.06, 0.76)
ON CONFLICT (nome_maquina) DO UPDATE
  SET meta_velocidade_virando                  = EXCLUDED.meta_velocidade_virando,
      meta_indisponibilidade_virando_gerencial = EXCLUDED.meta_indisponibilidade_virando_gerencial,
      meta_indisponibilidade_virando_area      = EXCLUDED.meta_indisponibilidade_virando_area,
      meta_acerto_mesma_faca                   = EXCLUDED.meta_acerto_mesma_faca,
      meta_acerto_troca_faca                   = EXCLUDED.meta_acerto_troca_faca;

-- 3. Atualiza printiag_meta_vel_familia
DELETE FROM printiag_meta_vel_familia
  WHERE familia_virando LIKE 'AMBITION%'
     OR familia_virando LIKE 'EXPERTFOLD%'
     OR familia_virando LIKE 'NOVAFOLD%';

INSERT INTO printiag_meta_vel_familia (familia_virando, meta_velocidade_virando) VALUES
  ('Coladeira AmbitionBraille - Cartão',              11889),
  ('Coladeira AmbitionFundo Automático - Cartão',      9856),
  ('Coladeira AmbitionFundo Automático - Micro',       3049),
  ('Coladeira AmbitionLateral - Cartão',               16296),
  ('Coladeira AmbitionNicho - Cartão',                 5238),
  ('Coladeira ExpertfoldAplicação Braille - Cartão',  33933),
  ('Coladeira ExpertfoldBraille - Cartão',             16908),
  ('Coladeira ExpertfoldFundo Automático - Cartão',   32055),
  ('Coladeira ExpertfoldLateral - Cartão',             49451),
  ('Coladeira NovafoldAplicação Braille - Cartão',   22373),
  ('Coladeira NovafoldBraille - Cartão',              13850),
  ('Coladeira NovafoldFundo Automático - Cartão',    10752),
  ('Coladeira NovafoldFundo Automático - Micro',       2998),
  ('Coladeira NovafoldLateral - Cartão',              21873),
  ('Coladeira NovafoldLateral - Micro',               2968),
  ('Coladeira NovafoldNicho - Cartão',               10011)
ON CONFLICT (familia_virando) DO UPDATE
  SET meta_velocidade_virando = EXCLUDED.meta_velocidade_virando;

-- 4. Recria a MV com o JOIN corrigido
-- (necessário porque nome_maquina agora baterá com o CSV)

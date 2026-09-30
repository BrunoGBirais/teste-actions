-- =====================================================================
-- 025_classificacao_outras_areas.sql
--
-- O seed de 008 cobria só os motivos das coladeiras. Com os apontamentos
-- de Impressão, Hot Stamping, Corte e Vinco e Corte de Papel já na base,
-- ~7.700 linhas ficaram sem par em printiag_classificacao.
--
-- Como o join da MV é LEFT (010 L64-71), essas linhas entram com
-- classificacao_perda = NULL, não caem em nenhum bucket de hora e somem
-- de todos os indicadores — sem erro, sem aviso.
--
-- ⚠️ AS CLASSIFICAÇÕES ABAIXO SÃO UMA PROPOSTA, NÃO UM FATO.
--    Foram inferidas pelo nome do motivo. Os marcados com (?) são os que
--    mais mudam resultado e precisam de confirmação da produção antes de
--    virarem número oficial. Revise na tela de Classificações.
--
-- ⚠️ A chave NÃO tem máquina: é só tipo_apontam || motivo. Se algum destes
--    motivos também for usado nas coladeiras, classificá-lo MUDA os
--    indicadores de Acabamento. Rode a query de conferência do rodapé
--    antes de aplicar.
--
-- Dependência: aplicar depois de 022 (que criou uq_pclass_chave_norm).
-- =====================================================================

-- =======  UP  ========

BEGIN;

-- DO NOTHING de propósito: nunca sobrescreve decisão já registrada.
INSERT INTO printiag_classificacao
  (chave, tipo_apontam, motivo, classificacao_perda, atuacao, nivel_atuacao)
VALUES
  -- ---- Preparação de máquina / ferramental → Acerto ----
  ('OciosoConfecção de Canaleta',        'Ocioso',   'Confecção de Canaleta',        'Acerto', 'Acerto', 'Operacional'), -- (?) 1762 linhas
  ('OciosoPreparação de Fita HS',        'Ocioso',   'Preparação de Fita HS',        'Acerto', 'Acerto', 'Operacional'),
  ('OciosoAjuste do Destacador',         'Ocioso',   'Ajuste do Destacador',         'Acerto', 'Acerto', 'Operacional'),
  ('OciosoMontagem do Destacador',       'Ocioso',   'Montagem do Destacador',       'Acerto', 'Acerto', 'Operacional'),
  ('OciosoMontagem Clichê HS',           'Ocioso',   'Montagem Clichê HS',           'Acerto', 'Acerto', 'Operacional'),
  ('OciosoDesmontando Clichê HS',        'Ocioso',   'Desmontando Clichê HS',        'Acerto', 'Acerto', 'Operacional'),
  ('OciosoAquecendo Máquina HS',         'Ocioso',   'Aquecendo Máquina HS',         'Acerto', 'Acerto', 'Operacional'), -- (?) pode ser Operacional Planejado
  ('OciosoAjuste de Relevo',             'Ocioso',   'Ajuste de Relevo',             'Acerto', 'Acerto', 'Operacional'),
  ('OciosoTroca de Faca',                'Ocioso',   'Troca de Faca',                'Acerto', 'Acerto', 'Operacional'), -- (?) verificar se ocorre nas coladeiras
  ('AcertoPreparação de Máquina',        'Acerto',   'Preparação de Máquina',        'Acerto', 'Acerto', 'Operacional'),
  ('AcertoConfecção de Canaleta',        'Acerto',   'Confecção de Canaleta',        'Acerto', 'Acerto', 'Operacional'),

  -- ---- Espera por insumo ou etapa anterior → Aguardando ----
  ('OciosoAguardando Esfriamento da Rama', 'Ocioso', 'Aguardando Esfriamento da Rama', 'Aguardando', 'Área', 'Liderança'),
  ('OciosoAguardando Bobina',            'Ocioso',   'Aguardando Bobina',            'Aguardando', 'Área', 'Liderança'),
  ('OciosoAguardando Material',          'Ocioso',   'Aguardando Material',          'Aguardando', 'Área', 'Liderança'),
  ('OciosoAguardando Preparação de Tinta','Ocioso',  'Aguardando Preparação de Tinta','Aguardando', 'Área', 'Liderança'),
  ('OciosoFalta de Palete',              'Ocioso',   'Falta de Palete',              'Aguardando', 'Área', 'Liderança'),
  ('OciosoSem Pallet',                   'Ocioso',   'Sem Pallet',                   'Aguardando', 'Área', 'Liderança'),
  ('ProduçãoAguardando Bobina',          'Produção', 'Aguardando Bobina',            'Aguardando', 'Área', 'Liderança'),

  -- ---- Retrabalho / desvio de processo → Problema de Processo ----
  -- Segue o precedente do seed: 'Gravacao Chapa Impressao' e
  -- 'Preparacao de Tinta' já eram Problema de Processo.
  ('OciosoRaspando Chapa',               'Ocioso',   'Raspando Chapa',               'Problema de Processo', 'Área', 'Liderança'), -- (?) 1231 linhas
  ('OciosoAjuste de Tinta',              'Ocioso',   'Ajuste de Tinta',              'Problema de Processo', 'Área', 'Liderança'),
  ('OciosoGravação de Chapa no Acerto',  'Ocioso',   'Gravação de Chapa no Acerto',  'Problema de Processo', 'Área', 'Liderança'), -- (?) pode ser Acerto
  ('OciosoGravação de Chapa na Produção','Ocioso',   'Gravação de Chapa na Produção','Problema de Processo', 'Área', 'Liderança'),
  ('OciosoTroca de Blanqueta',           'Ocioso',   'Troca de Blanqueta',           'Problema de Processo', 'Área', 'Liderança'), -- (?) pode ser Manutenção

  -- ---- Tarefa manual prevista → Operacional Planejado ----
  ('OciosoOperador Batendo Pilha',       'Ocioso',   'Operador Batendo Pilha',       'Operacional Planejado', 'Área', 'Liderança'),
  ('OciosoRebatendo Pilha',              'Ocioso',   'Rebatendo Pilha',              'Operacional Planejado', 'Área', 'Liderança'),

  -- ---- Operador ausente da máquina → Sem Tripulação ----
  -- Mesmo tratamento de 'Operadores em Outra Maquina' no seed.
  ('OciosoOperador na Guilhotina',       'Ocioso',   'Operador na Guilhotina',       'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('OciosoPortaria',                     'Ocioso',   'Portaria',                     'Sem Tripulação', 'Gerencial', 'Gerencial'),
  ('ProduçãoEq deslocada para outra máq','Produção', 'Eq deslocada para outra máq',  'Sem Tripulação', 'Gerencial', 'Gerencial'),

  -- ---- Manutenção programada ----
  ('AcertoManutenção Preventiva',        'Acerto',   'Manutenção Preventiva',        'Manutenção Preventiva', 'Gerencial', 'Gerencial'),

  -- ---- Ocioso sem motivo preenchido ----
  -- chave = norm('Ocioso') || norm('') = 'ocioso'
  ('Ocioso',                             'Ocioso',   '',                             'Sem Apontamento', 'Sem Apontamento', 'Gerencial')

ON CONFLICT (chave_norm) DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------------
-- ANTES de aplicar — quais máquinas usam cada motivo?
-- Se alguma coladeira aparecer, os indicadores de Acabamento vão mudar.
--
--   SELECT a.tipo_apontam, a.motivo,
--          string_agg(DISTINCT a.equipamento, ', ') AS maquinas,
--          count(*) AS qtd
--   FROM printag_apontamentos a
--   WHERE NOT EXISTS (SELECT 1 FROM printiag_classificacao c
--                     WHERE c.chave_norm = a.chave)
--   GROUP BY 1, 2
--   ORDER BY qtd DESC;
--
-- DEPOIS de aplicar:
--   SELECT printag_refresh_base();
--   -- deve retornar zero linhas:
--   SELECT count(*) FROM printag_apontamentos a
--   WHERE NOT EXISTS (SELECT 1 FROM printiag_classificacao c
--                     WHERE c.chave_norm = a.chave);
--
--   -- e o Acabamento não pode ter mudado:
--   SELECT * FROM printag_ind_improdutivos_semana(2026, NULL, NULL, NULL, NULL);
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- DELETE FROM printiag_classificacao WHERE chave IN (
--   'OciosoConfecção de Canaleta', 'OciosoPreparação de Fita HS',
--   'OciosoAjuste do Destacador', 'OciosoMontagem do Destacador',
--   'OciosoMontagem Clichê HS', 'OciosoDesmontando Clichê HS',
--   'OciosoAquecendo Máquina HS', 'OciosoAjuste de Relevo',
--   'OciosoTroca de Faca', 'AcertoPreparação de Máquina',
--   'AcertoConfecção de Canaleta', 'OciosoAguardando Esfriamento da Rama',
--   'OciosoAguardando Bobina', 'OciosoAguardando Material',
--   'OciosoAguardando Preparação de Tinta', 'OciosoFalta de Palete',
--   'OciosoSem Pallet', 'ProduçãoAguardando Bobina', 'OciosoRaspando Chapa',
--   'OciosoAjuste de Tinta', 'OciosoGravação de Chapa no Acerto',
--   'OciosoGravação de Chapa na Produção', 'OciosoTroca de Blanqueta',
--   'OciosoOperador Batendo Pilha', 'OciosoRebatendo Pilha',
--   'OciosoOperador na Guilhotina', 'OciosoPortaria',
--   'ProduçãoEq deslocada para outra máq', 'AcertoManutenção Preventiva',
--   'Ocioso');

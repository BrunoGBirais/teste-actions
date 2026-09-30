-- =========================================================
-- PrintAG — 010: Materialized View mv_base_apontamentos
-- Equivalente à aba "Base" do Excel: join de apontamentos
-- com dimensões, forward-fill de OS + faca, colunas OEE.
-- =========================================================

-- A MV precisa de um índice único para suportar REFRESH CONCURRENTLY.
-- Criamos a MV primeiro sem dados para definir o índice.

DROP MATERIALIZED VIEW IF EXISTS mv_base_apontamentos;

CREATE MATERIALIZED VIEW mv_base_apontamentos AS

-- ---- FASE 1: base ----
-- Junta apontamentos com máquinas e classificação OEE.
-- Os joins usam norm() para tolerância de variações de grafia.
WITH base AS (
  SELECT
    a.id,
    a.equipamento,
    a.tipo_apontam,
    a.motivo,
    a.inicio,
    a.fim,
    NULLIF(trim(a.nro_os), '') AS nro_os,
    a.produzido,
    a.titulo_produto,
    a.nome_cliente,
    a.operador,

    -- decomposição temporal (fuso horário BR)
    ROUND((EXTRACT(EPOCH FROM (a.fim - a.inicio)) / 3600.0)::NUMERIC, 2) AS tempo_total,
    (a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE            AS data,
    EXTRACT(YEAR  FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS ano,
    EXTRACT(MONTH FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS mes,
    EXTRACT(DAY   FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS dia,
    EXTRACT(WEEK  FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS semana,

    -- campo unificado apontamento (motivo se existir, senão tipo_apontam)
    COALESCE(NULLIF(trim(a.motivo), ''), a.tipo_apontam)         AS apontamento,

    -- chave de classificação (= printag_apontamentos.chave)
    norm(a.tipo_apontam) || norm(COALESCE(a.motivo, ''))         AS chave,

    -- dimensão máquina
    m.id                  AS maquina_id,
    m.nome_maquina,
    m.area,
    m.velocidade          AS velocidade_mecanica,

    -- dimensão classificação OEE
    c.classificacao_id,
    c.classificacao_perda,
    c.atuacao             AS classificacao_oee,
    c.nivel_atuacao

  FROM printag_apontamentos a
  LEFT JOIN printiag_maquinas m
         ON m.nome_norm = norm(a.equipamento)
  -- JOIN por chave normalizada. LATERAL + LIMIT 1 para que variantes de grafia
  -- (ex: 'OciosoRefeicao' e 'OciosoRefeição' → ambas normalizam para 'ociosorefeicao')
  -- não produzam linhas duplicadas no MV.
  -- A.chave já é GENERATED AS norm(tipo_apontam)||norm(COALESCE(motivo,'')) em printag_apontamentos.
  LEFT JOIN LATERAL (
    SELECT id AS classificacao_id, classificacao_perda, atuacao, nivel_atuacao
    FROM printiag_classificacao
    WHERE chave_norm = a.chave
    ORDER BY id  -- determinístico: primeira linha cadastrada vence
    LIMIT 1
  ) c ON TRUE
),

-- ---- FASE 2: forward-fill de nro_os (islands and gaps) ----
-- A cada vez que aparece um nro_os não nulo, começa um novo "grupo".
-- O FIRST_VALUE propaga o nro_os para as linhas sem OS abaixo dele.
os_group AS (
  SELECT *,
    SUM(
      CASE WHEN nro_os IS NOT NULL AND nro_os <> '' THEN 1 ELSE 0 END
    ) OVER (PARTITION BY maquina_id ORDER BY inicio
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp_os
  FROM base
),
os_filled AS (
  SELECT *,
    FIRST_VALUE(nro_os) OVER (
      PARTITION BY maquina_id, grp_os ORDER BY inicio
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS os_corrida
  FROM os_group
),

-- ---- FASE 3: lookup de acabamento, faca e micro ----
with_lookups AS (
  SELECT
    f.*,
    -- tipo de acabamento planejado (via OS corrida → printag_acabamentos)
    ac.raw_tipo_acabamento,
    -- categoria de dobra (via printiag_acabamento_auxiliar)
    aa.acabamento               AS tipo_acabamento,
    -- faca associada à OS (primeira faca encontrada)
    fac.faca                    AS numero_faca_raw,
    -- micro vs cartão (default 'micro' se não mapeado)
    COALESCE(bm.tipo, 'Cartão') AS micro  -- OS não mapeada = Cartão por padrão

  FROM os_filled f
  LEFT JOIN LATERAL (
    -- primeira OS corrida encontrada (evita duplicatas se houver múltiplas linhas por OS)
    -- nro_os já normalizado (sem zeros à esquerda) pelo RPC de upload
    SELECT tipo_acabamento AS raw_tipo_acabamento
    FROM printag_acabamentos
    WHERE nro_os = f.os_corrida
    ORDER BY id LIMIT 1
  ) ac ON TRUE
  LEFT JOIN printiag_acabamento_auxiliar aa
         ON norm(aa.descricao) = norm(ac.raw_tipo_acabamento)
  LEFT JOIN LATERAL (
    -- apenas a primeira faca da OS (pode haver múltiplas)
    -- nro_os já normalizado (sem zeros à esquerda) pelo RPC de upload
    SELECT faca FROM printag_facas WHERE nro_os = f.os_corrida LIMIT 1
  ) fac ON TRUE
  LEFT JOIN printiag_base_micro bm ON bm.os = f.os_corrida
),

-- tipo_virando = tipo_acabamento + ' - ' + micro
-- Ex: 'Fundo Automático' + ' - ' + 'Cartão' = 'Fundo Automático - Cartão'
with_virando AS (
  SELECT *,
    CASE
      WHEN tipo_acabamento IS NOT NULL
      THEN tipo_acabamento || ' - ' || micro
    END AS tipo_virando
  FROM with_lookups
),

-- ---- FASE 4: forward-fill de numero_faca + tipo_acerto ----
faca_group AS (
  SELECT *,
    SUM(
      CASE WHEN numero_faca_raw IS NOT NULL THEN 1 ELSE 0 END
    ) OVER (PARTITION BY maquina_id ORDER BY inicio
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS grp_faca
  FROM with_virando
),
with_faca AS (
  SELECT *,
    FIRST_VALUE(numero_faca_raw) OVER (
      PARTITION BY maquina_id, grp_faca ORDER BY inicio
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS numero_faca
  FROM faca_group
),
with_acerto AS (
  SELECT *,
    -- tipo_acerto: compara faca forward-filled atual com a do apontamento anterior
    -- numero_faca já foi calculado em with_faca — sem necessidade de aninhar window functions
    CASE
      WHEN numero_faca = LAG(numero_faca) OVER (PARTITION BY maquina_id ORDER BY inicio)
      THEN 'Mesma Faca'
      ELSE 'Troca de Faca'
    END AS tipo_acerto,
    -- flag de início de nova OS
    CASE
      WHEN os_corrida IS DISTINCT FROM
           LAG(os_corrida) OVER (PARTITION BY maquina_id ORDER BY inicio)
      THEN 1 ELSE 0
    END AS acerto_para_os
  FROM with_faca
)

-- ---- SELECT FINAL ----
SELECT
  wf.id,
  wf.equipamento,
  wf.tipo_apontam,
  wf.motivo,
  wf.inicio,
  wf.fim,
  wf.nro_os,
  wf.produzido,
  wf.titulo_produto,
  wf.nome_cliente,
  wf.operador,

  wf.tempo_total,
  wf.data,
  wf.ano,
  wf.mes,
  wf.dia,
  wf.semana,
  wf.apontamento,
  wf.chave,

  wf.maquina_id,
  wf.nome_maquina,
  wf.area,
  wf.velocidade_mecanica,

  wf.classificacao_id,
  wf.classificacao_perda,
  wf.classificacao_oee,
  wf.nivel_atuacao,

  wf.os_corrida,
  wf.raw_tipo_acabamento,
  wf.tipo_acabamento,
  wf.tipo_virando,
  wf.numero_faca,
  wf.micro,
  wf.tipo_acerto,
  wf.acerto_para_os,

  -- ---- Buckets de horas por tipo de perda ----
  CASE WHEN wf.classificacao_perda = 'Virando'               THEN wf.tempo_total END AS virando_hrs,
  CASE WHEN wf.classificacao_perda = 'Acerto'                THEN wf.tempo_total END AS acerto_hrs,
  CASE WHEN wf.classificacao_perda = 'Sem Apontamento'       THEN wf.tempo_total END AS nao_tripulado_hrs,
  CASE WHEN wf.classificacao_perda = 'Sem Serviço'           THEN wf.tempo_total END AS sem_servico_hrs,
  CASE WHEN wf.classificacao_perda = 'Sem Tripulação'        THEN wf.tempo_total END AS sem_tripulacao_hrs,
  CASE WHEN wf.classificacao_perda = 'Operacional Planejado' THEN wf.tempo_total END AS operacional_planejado_hrs,
  CASE WHEN wf.classificacao_perda = 'Manutenção Preventiva' THEN wf.tempo_total END AS manutencao_preventiva_hrs,
  CASE WHEN wf.classificacao_perda = 'Problema de Processo'  THEN wf.tempo_total END AS problemas_de_processo_hrs,
  CASE WHEN wf.classificacao_perda = 'Manutenção Corretiva'  THEN wf.tempo_total END AS manutencao_corretiva_hrs,
  CASE WHEN wf.classificacao_perda = 'Aguardando'            THEN wf.tempo_total END AS aguardando_hrs,

  -- ---- Horas improdutivas OEE ----
  CASE WHEN wf.classificacao_oee = 'Gerencial'               THEN wf.tempo_total END AS horas_improdutivas_gerencial,
  CASE WHEN wf.classificacao_oee = 'Área'                    THEN wf.tempo_total END AS horas_improdutivas_area,

  -- ---- Quantidade de acertos ----
  CASE WHEN wf.tipo_apontam = 'Acerto'
            OR norm(wf.motivo) = 'liberacao de maquina'
       THEN 1
       ELSE 0
  END AS quantidade_acerto,

  -- ---- Quantidade produzida (imputada) ----
  CASE WHEN wf.classificacao_perda = 'Virando'
       THEN wf.velocidade_mecanica * wf.tempo_total
  END AS qtd_produzida_virando,

  CASE WHEN wf.classificacao_oee IN ('Virando', 'Acerto', 'Área')
       THEN wf.velocidade_mecanica * wf.tempo_total
  END AS qtd_produzida_oee_operacional,

  wf.velocidade_mecanica * wf.tempo_total AS qtd_produzida_oee_gerencial,

  -- ---- Metas ----
  meta.meta_velocidade_virando
    * CASE WHEN wf.classificacao_perda = 'Virando' THEN wf.tempo_total ELSE 0 END
    AS qtd_produzida_meta_vel_virando,


  fam.meta_velocidade_virando
    * CASE WHEN wf.classificacao_perda = 'Virando' THEN wf.tempo_total ELSE 0 END
    AS qtd_produzida_meta_vel_familia,

  CASE WHEN wf.tipo_acerto = 'Mesma Faca'
       THEN meta.meta_acerto_mesma_faca
       ELSE meta.meta_acerto_troca_faca
  END
  * CASE WHEN wf.tipo_apontam = 'Acerto'
              OR norm(wf.motivo) = 'liberacao de maquina'
         THEN 1 ELSE 0
    END AS meta_acerto,

  meta.meta_indisponibilidade_virando_gerencial * wf.tempo_total AS meta_horas_imp_ger,

  CASE WHEN wf.classificacao_oee IN ('Área', 'Virando')
       THEN meta.meta_indisponibilidade_virando_area * wf.tempo_total
  END AS meta_horas_imp_area

FROM with_acerto wf
LEFT JOIN printiag_metas_maquinas meta
       ON meta.nome_maquina = wf.nome_maquina
LEFT JOIN printiag_meta_vel_familia fam
       ON fam.familia_virando = wf.equipamento || wf.tipo_virando
WITH NO DATA;

-- ---- Índice único obrigatório para REFRESH CONCURRENTLY ----
CREATE UNIQUE INDEX ON mv_base_apontamentos (id);

-- ---- Índices para filtros de dashboard ----
CREATE INDEX ON mv_base_apontamentos (maquina_id, ano, semana);
CREATE INDEX ON mv_base_apontamentos (ano, semana);
CREATE INDEX ON mv_base_apontamentos (tipo_acabamento);
CREATE INDEX ON mv_base_apontamentos (operador);
CREATE INDEX ON mv_base_apontamentos (classificacao_perda);
CREATE INDEX ON mv_base_apontamentos (data DESC);

-- =====================================================================
-- 031_agente_faca_e_granularidade.sql
--
-- O agente de IA foi desenhado antes de a planilha de negócio estar
-- fechada. Comparando o que o usuário realmente pergunta com o que as
-- RPCs entregam, sobraram quatro buracos:
--
--   1. A planilha "Levantamento Metros Lineares e Montagem" traz
--      Faca, Largura do Cartucho (faca.Lado 1), Altura do Cartucho
--      (faca.Lado 2) e Montagem. A MV só puxava `faca` de
--      printag_facas — largura, altura e montagem eram invisíveis
--      para o agente, apesar de já estarem carregadas na tabela.
--   2. O usuário desdobra por DIA, semana, mês e ano; as RPCs só
--      sabiam semana e mês.
--   3. "Tipo de Acerto" (Mesma Faca / Troca de Faca) existe na MV
--      desde a 010, mas não era nem filtro nem dimensão de ranking.
--   4. Não havia como recortar por intervalo de datas — só por
--      número de semana/mês, o que trava perguntas como
--      "última quinzena".
--
-- Esta migration:
--   - recria a MV acrescentando largura_cartucho, altura_cartucho e
--     montagem (forward-fill junto com numero_faca, mesmo grp_faca);
--   - recria as 6 RPCs do agente com granularidade dia|semana|mes|ano,
--     rótulo legível do período, filtro por tipo_acerto e por intervalo
--     de datas, e novas dimensões de ranking;
--   - cria printag_dados_faca, a tool que responde sobre a planilha de
--     facas (dimensões do cartucho + montagem + KPIs da OS).
--
-- Nada do dashboard muda: as RPCs printag_ind_* / printag_indm_*
-- continuam iguais e leem as mesmas colunas de sempre.
-- =====================================================================

-- =======  UP  ========

-- =========================================================
-- 1. mv_base_apontamentos
-- + largura_cartucho, altura_cartucho, montagem
-- Resto do corpo idêntico à 010.
-- =========================================================
DROP MATERIALIZED VIEW IF EXISTS mv_base_apontamentos;

CREATE MATERIALIZED VIEW mv_base_apontamentos AS

-- ---- FASE 1: base ----
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

    ROUND((EXTRACT(EPOCH FROM (a.fim - a.inicio)) / 3600.0)::NUMERIC, 2) AS tempo_total,
    (a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE            AS data,
    EXTRACT(YEAR  FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS ano,
    EXTRACT(MONTH FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS mes,
    EXTRACT(DAY   FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS dia,
    EXTRACT(WEEK  FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS semana,

    COALESCE(NULLIF(trim(a.motivo), ''), a.tipo_apontam)         AS apontamento,
    norm(a.tipo_apontam) || norm(COALESCE(a.motivo, ''))         AS chave,

    m.id                  AS maquina_id,
    m.nome_maquina,
    m.area,
    m.velocidade          AS velocidade_mecanica,

    c.classificacao_id,
    c.classificacao_perda,
    c.atuacao             AS classificacao_oee,
    c.nivel_atuacao

  FROM printag_apontamentos a
  LEFT JOIN printiag_maquinas m
         ON m.nome_norm = norm(a.equipamento)
  LEFT JOIN LATERAL (
    SELECT id AS classificacao_id, classificacao_perda, atuacao, nivel_atuacao
    FROM printiag_classificacao
    WHERE chave_norm = a.chave
    ORDER BY id
    LIMIT 1
  ) c ON TRUE
),

-- ---- FASE 2: forward-fill de nro_os (islands and gaps) ----
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
    ac.raw_tipo_acabamento,
    aa.acabamento               AS tipo_acabamento,
    -- faca da OS + dimensões do cartucho (planilha de metros lineares)
    fac.faca                    AS numero_faca_raw,
    fac.lado_1                  AS largura_cartucho_raw,
    fac.lado_2                  AS altura_cartucho_raw,
    fac.montagem                AS montagem_raw,
    COALESCE(bm.tipo, 'Cartão') AS micro

  FROM os_filled f
  LEFT JOIN LATERAL (
    SELECT tipo_acabamento AS raw_tipo_acabamento
    FROM printag_acabamentos
    WHERE nro_os = f.os_corrida
    ORDER BY id LIMIT 1
  ) ac ON TRUE
  LEFT JOIN printiag_acabamento_auxiliar aa
         ON norm(aa.descricao) = norm(ac.raw_tipo_acabamento)
  LEFT JOIN LATERAL (
    -- apenas a primeira faca da OS (pode haver múltiplas)
    SELECT faca, lado_1, lado_2, montagem
    FROM printag_facas
    WHERE nro_os = f.os_corrida
    ORDER BY id LIMIT 1
  ) fac ON TRUE
  LEFT JOIN printiag_base_micro bm ON bm.os = f.os_corrida
),

with_virando AS (
  SELECT *,
    CASE
      WHEN tipo_acabamento IS NOT NULL
      THEN tipo_acabamento || ' - ' || micro
    END AS tipo_virando
  FROM with_lookups
),

-- ---- FASE 4: forward-fill de numero_faca (+ dimensões) e tipo_acerto ----
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
    FIRST_VALUE(numero_faca_raw) OVER w        AS numero_faca,
    -- as dimensões viajam junto com a faca: mesmo grupo, mesma janela
    FIRST_VALUE(largura_cartucho_raw) OVER w   AS largura_cartucho,
    FIRST_VALUE(altura_cartucho_raw)  OVER w   AS altura_cartucho,
    FIRST_VALUE(montagem_raw)         OVER w   AS montagem
  FROM faca_group
  WINDOW w AS (
    PARTITION BY maquina_id, grp_faca ORDER BY inicio
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )
),
with_acerto AS (
  SELECT *,
    CASE
      WHEN numero_faca = LAG(numero_faca) OVER (PARTITION BY maquina_id ORDER BY inicio)
      THEN 'Mesma Faca'
      ELSE 'Troca de Faca'
    END AS tipo_acerto,
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
  wf.largura_cartucho,
  wf.altura_cartucho,
  wf.montagem,
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
WITH DATA;

CREATE UNIQUE INDEX ON mv_base_apontamentos (id);
CREATE INDEX ON mv_base_apontamentos (maquina_id, ano, semana);
CREATE INDEX ON mv_base_apontamentos (ano, semana);
CREATE INDEX ON mv_base_apontamentos (ano, mes);
CREATE INDEX ON mv_base_apontamentos (tipo_acabamento);
CREATE INDEX ON mv_base_apontamentos (operador);
CREATE INDEX ON mv_base_apontamentos (classificacao_perda);
CREATE INDEX ON mv_base_apontamentos (data DESC);
CREATE INDEX ON mv_base_apontamentos (os_corrida);
CREATE INDEX ON mv_base_apontamentos (numero_faca);
CREATE INDEX ON mv_base_apontamentos (tipo_acerto);


-- =========================================================
-- 2. Helpers de granularidade
-- Um único lugar decide o que é "dia", "semana", "mes" e "ano",
-- para as 4 RPCs de série temporal não divergirem entre si.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_gran_norm(p_gran TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(COALESCE(NULLIF(trim(p_gran), ''), 'semana'))
    WHEN 'dia'     THEN 'dia'
    WHEN 'diario'  THEN 'dia'
    WHEN 'diário'  THEN 'dia'
    WHEN 'diaria'  THEN 'dia'
    WHEN 'diária'  THEN 'dia'
    WHEN 'data'    THEN 'dia'
    WHEN 'd'       THEN 'dia'
    WHEN 'day'     THEN 'dia'
    WHEN 'daily'   THEN 'dia'
    WHEN 'mes'     THEN 'mes'
    WHEN 'mês'     THEN 'mes'
    WHEN 'mensal'  THEN 'mes'
    WHEN 'm'       THEN 'mes'
    WHEN 'month'   THEN 'mes'
    WHEN 'monthly' THEN 'mes'
    WHEN 'ano'     THEN 'ano'
    WHEN 'anual'   THEN 'ano'
    WHEN 'a'       THEN 'ano'
    WHEN 'year'    THEN 'ano'
    WHEN 'yearly'  THEN 'ano'
    ELSE 'semana'
  END;
$$;

-- Chave numérica ordenável do período.
--   dia    → 20260827 (AAAAMMDD)   semana → 34
--   mes    → 8                     ano    → 2026
CREATE OR REPLACE FUNCTION printag_gran_periodo(
  p_gran TEXT, p_ano INT, p_mes INT, p_semana INT, p_dia INT
)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE printag_gran_norm(p_gran)
    WHEN 'dia' THEN p_ano * 10000 + p_mes * 100 + p_dia
    WHEN 'mes' THEN p_mes
    WHEN 'ano' THEN p_ano
    ELSE p_semana
  END;
$$;

-- Rótulo legível, para o agente montar tabela sem inventar formato.
CREATE OR REPLACE FUNCTION printag_gran_label(
  p_gran TEXT, p_ano INT, p_mes INT, p_semana INT, p_dia INT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE printag_gran_norm(p_gran)
    WHEN 'dia' THEN lpad(p_dia::TEXT, 2, '0') || '/' || lpad(p_mes::TEXT, 2, '0')
                    || '/' || p_ano::TEXT
    WHEN 'mes' THEN lpad(p_mes::TEXT, 2, '0') || '/' || p_ano::TEXT
    WHEN 'ano' THEN p_ano::TEXT
    ELSE 'S' || lpad(p_semana::TEXT, 2, '0') || '/' || p_ano::TEXT
  END;
$$;

GRANT EXECUTE ON FUNCTION printag_gran_norm(TEXT)                       TO authenticated;
GRANT EXECUTE ON FUNCTION printag_gran_periodo(TEXT, INT, INT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_gran_label(TEXT, INT, INT, INT, INT)   TO authenticated;


-- =========================================================
-- 3. printag_kpi_periodo
-- + granularidade dia|ano, + periodo_label, + filtro por
-- tipo_acerto e por intervalo de datas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE);

CREATE FUNCTION printag_kpi_periodo(
  p_gran         TEXT    DEFAULT 'semana',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL,
  p_tipos_acerto TEXT[]  DEFAULT NULL,
  p_data_ini     DATE    DEFAULT NULL,
  p_data_fim     DATE    DEFAULT NULL
)
RETURNS TABLE (
  periodo                  INT,
  periodo_label            TEXT,
  acerto_hrs               NUMERIC,
  quantidade_acerto        BIGINT,
  tempo_medio_acerto_h     NUMERIC,
  meta_acerto_total        NUMERIC,
  desvio_acerto_h          NUMERIC,
  virando_hrs              NUMERIC,
  produzido_virando        BIGINT,
  vel_real_pech            NUMERIC,
  vel_meta_pech            NUMERIC,
  vel_produzindo_pech      NUMERIC,
  improd_area_h            NUMERIC,
  meta_improd_area_h       NUMERIC,
  improd_pct               NUMERIC,
  meta_improd_pct          NUMERIC,
  improd_gerencial_h       NUMERIC,
  improd_ger_pct           NUMERIC,
  tiragem_media_pec_acerto NUMERIC,
  produzido_total          BIGINT,
  tempo_total              NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    printag_gran_periodo(p_gran, ano, mes, semana, dia)      AS periodo,
    printag_gran_label(p_gran, ano, mes, semana, dia)        AS periodo_label,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    SUM(quantidade_acerto)::BIGINT                           AS quantidade_acerto,
    ROUND((SUM(acerto_hrs)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 2) AS tempo_medio_acerto_h,
    ROUND(SUM(meta_acerto)::NUMERIC, 2)                      AS meta_acerto_total,
    ROUND((SUM(acerto_hrs) - SUM(meta_acerto))::NUMERIC, 2)  AS desvio_acerto_h,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(qtd_produzida_meta_vel_virando)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_meta_pech,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS vel_produzindo_pech,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC, 2)              AS meta_improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS improd_pct,
    ROUND((SUM(meta_horas_imp_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS meta_improd_pct,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 2)     AS improd_gerencial_h,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                      AS tempo_total
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_tipos_acerto IS NULL OR tipo_acerto     = ANY(p_tipos_acerto))
    AND (p_data_ini     IS NULL OR data           >= p_data_ini)
    AND (p_data_fim     IS NULL OR data           <= p_data_fim)
    AND (p_periodos     IS NULL
         OR printag_gran_periodo(p_gran, ano, mes, semana, dia) = ANY(p_periodos))
  GROUP BY 1, 2
  ORDER BY 1;
$$;


-- =========================================================
-- 4. printag_kpi_disponibilidade
-- Mesmos filtros e granularidade da kpi_periodo.
-- =========================================================
DROP FUNCTION IF EXISTS printag_kpi_disponibilidade(TEXT, INT, INT[], INT[], TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS printag_kpi_disponibilidade(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE);

CREATE FUNCTION printag_kpi_disponibilidade(
  p_gran         TEXT    DEFAULT 'semana',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL,
  p_tipos_acerto TEXT[]  DEFAULT NULL,
  p_data_ini     DATE    DEFAULT NULL,
  p_data_fim     DATE    DEFAULT NULL
)
RETURNS TABLE (
  periodo                   INT,
  periodo_label             TEXT,
  tempo_total               NUMERIC,
  virando_hrs               NUMERIC,
  acerto_hrs                NUMERIC,
  operacional_planejado_hrs NUMERIC,
  problemas_de_processo_hrs NUMERIC,
  manutencao_corretiva_hrs  NUMERIC,
  manutencao_preventiva_hrs NUMERIC,
  aguardando_hrs            NUMERIC,
  sem_tripulacao_hrs        NUMERIC,
  sem_servico_hrs           NUMERIC,
  sem_classificacao_hrs     NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    printag_gran_periodo(p_gran, ano, mes, semana, dia)  AS periodo,
    printag_gran_label(p_gran, ano, mes, semana, dia)    AS periodo_label,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                  AS tempo_total,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                  AS virando_hrs,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                   AS acerto_hrs,
    ROUND(SUM(operacional_planejado_hrs)::NUMERIC, 2)    AS operacional_planejado_hrs,
    ROUND(SUM(problemas_de_processo_hrs)::NUMERIC, 2)    AS problemas_de_processo_hrs,
    ROUND(SUM(manutencao_corretiva_hrs)::NUMERIC, 2)     AS manutencao_corretiva_hrs,
    ROUND(SUM(manutencao_preventiva_hrs)::NUMERIC, 2)    AS manutencao_preventiva_hrs,
    ROUND(SUM(aguardando_hrs)::NUMERIC, 2)               AS aguardando_hrs,
    ROUND(SUM(sem_tripulacao_hrs)::NUMERIC, 2)           AS sem_tripulacao_hrs,
    ROUND(SUM(sem_servico_hrs)::NUMERIC, 2)              AS sem_servico_hrs,
    -- apontamento ainda sem de-para: fica fora de todos os buckets acima,
    -- e é isso que explica um tempo_total que não fecha com a soma.
    ROUND(SUM(tempo_total) FILTER (WHERE classificacao_perda IS NULL)::NUMERIC, 2)
                                                         AS sem_classificacao_hrs
  FROM mv_base_apontamentos
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_tipos_acerto IS NULL OR tipo_acerto     = ANY(p_tipos_acerto))
    AND (p_data_ini     IS NULL OR data           >= p_data_ini)
    AND (p_data_fim     IS NULL OR data           <= p_data_fim)
    AND (p_periodos     IS NULL
         OR printag_gran_periodo(p_gran, ano, mes, semana, dia) = ANY(p_periodos))
  GROUP BY 1, 2
  ORDER BY 1;
$$;


-- =========================================================
-- 5. printag_kpi_yoy
-- + periodo_label, + filtros novos. Continua sendo a única
-- RPC que devolve dois anos.
-- =========================================================
DROP FUNCTION IF EXISTS printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[]);

CREATE FUNCTION printag_kpi_yoy(
  p_gran         TEXT    DEFAULT 'mes',
  p_ano          INT     DEFAULT NULL,
  p_periodos     INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL,
  p_tipos_acerto TEXT[]  DEFAULT NULL
)
RETURNS TABLE (
  ano                      INT,
  periodo                  INT,
  periodo_label            TEXT,
  acerto_hrs               NUMERIC,
  quantidade_acerto        BIGINT,
  tempo_medio_acerto_h     NUMERIC,
  virando_hrs              NUMERIC,
  produzido_virando        BIGINT,
  vel_real_pech            NUMERIC,
  vel_produzindo_pech      NUMERIC,
  improd_area_h            NUMERIC,
  improd_pct               NUMERIC,
  improd_ger_pct           NUMERIC,
  tiragem_media_pec_acerto NUMERIC,
  produzido_total          BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mv.ano,
    printag_gran_periodo(p_gran, mv.ano, mv.mes, mv.semana, mv.dia) AS periodo,
    printag_gran_label(p_gran, mv.ano, mv.mes, mv.semana, mv.dia)   AS periodo_label,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    SUM(quantidade_acerto)::BIGINT                           AS quantidade_acerto,
    ROUND((SUM(acerto_hrs)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 2) AS tempo_medio_acerto_h,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS vel_produzindo_pech,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS improd_pct,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total
  FROM mv_base_apontamentos mv
  WHERE maquina_id IS NOT NULL
    AND (p_ano          IS NULL OR mv.ano IN (p_ano, p_ano - 1))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_tipos_acerto IS NULL OR tipo_acerto     = ANY(p_tipos_acerto))
    AND (p_periodos     IS NULL
         OR printag_gran_periodo(p_gran, mv.ano, mv.mes, mv.semana, mv.dia) = ANY(p_periodos))
  GROUP BY mv.ano, 2, 3
  ORDER BY mv.ano, 2;
$$;


-- =========================================================
-- 6. printag_rank_dimensao
-- + dimensões tipo_acerto, tipo_virando, montagem e micro
-- + filtro por tipo_acerto e por intervalo de datas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE);

CREATE FUNCTION printag_rank_dimensao(
  p_dimensao     TEXT    DEFAULT 'operador',
  p_ano          INT     DEFAULT NULL,
  p_semanas      INT[]   DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL,
  p_tipos_acerto TEXT[]  DEFAULT NULL,
  p_data_ini     DATE    DEFAULT NULL,
  p_data_fim     DATE    DEFAULT NULL
)
RETURNS TABLE (
  item                     TEXT,
  item_id                  INT,
  acerto_hrs               NUMERIC,
  quantidade_acerto        BIGINT,
  tempo_medio_acerto_h     NUMERIC,
  meta_acerto_total        NUMERIC,
  desvio_acerto_h          NUMERIC,
  virando_hrs              NUMERIC,
  produzido_virando        BIGINT,
  vel_real_pech            NUMERIC,
  vel_meta_pech            NUMERIC,
  vel_produzindo_pech      NUMERIC,
  improd_area_h            NUMERIC,
  meta_improd_area_h       NUMERIC,
  improd_pct               NUMERIC,
  improd_gerencial_h       NUMERIC,
  improd_ger_pct           NUMERIC,
  tiragem_media_pec_acerto NUMERIC,
  produzido_total          BIGINT,
  tempo_total              NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH src AS (
    SELECT
      CASE lower(COALESCE(p_dimensao, 'operador'))
        WHEN 'maquina'         THEN nome_maquina
        WHEN 'máquina'         THEN nome_maquina
        WHEN 'area'            THEN area
        WHEN 'área'            THEN area
        WHEN 'tipo_acabamento' THEN tipo_acabamento
        WHEN 'acabamento'      THEN tipo_acabamento
        WHEN 'tipo_acerto'     THEN tipo_acerto
        WHEN 'acerto'          THEN tipo_acerto
        WHEN 'tipo_virando'    THEN tipo_virando
        WHEN 'familia'         THEN tipo_virando
        WHEN 'família'         THEN tipo_virando
        WHEN 'montagem'        THEN montagem::TEXT
        WHEN 'micro'           THEN micro
        WHEN 'substrato'       THEN micro
        WHEN 'os'              THEN os_corrida
        WHEN 'produto'         THEN titulo_produto
        WHEN 'cliente'         THEN nome_cliente
        WHEN 'faca'            THEN numero_faca
        ELSE operador
      END AS item_key,
      mv.*
    FROM mv_base_apontamentos mv
    WHERE maquina_id IS NOT NULL
      AND (p_ano          IS NULL OR ano             =  p_ano)
      AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
      AND (p_meses        IS NULL OR mes             = ANY(p_meses))
      AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
      AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
      AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
      AND (p_tipos_acerto IS NULL OR tipo_acerto     = ANY(p_tipos_acerto))
      AND (p_data_ini     IS NULL OR data           >= p_data_ini)
      AND (p_data_fim     IS NULL OR data           <= p_data_fim)
  )
  SELECT
    item_key                                                 AS item,
    CASE WHEN lower(COALESCE(p_dimensao,'operador')) IN ('maquina','máquina')
         THEN MAX(maquina_id) END                            AS item_id,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    SUM(quantidade_acerto)::BIGINT                           AS quantidade_acerto,
    ROUND((SUM(acerto_hrs)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 2) AS tempo_medio_acerto_h,
    ROUND(SUM(meta_acerto)::NUMERIC, 2)                      AS meta_acerto_total,
    ROUND((SUM(acerto_hrs) - SUM(meta_acerto))::NUMERIC, 2)  AS desvio_acerto_h,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)    AS produzido_virando,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(qtd_produzida_meta_vel_virando)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_meta_pech,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS vel_produzindo_pech,
    ROUND(SUM(horas_improdutivas_area)::NUMERIC, 2)          AS improd_area_h,
    ROUND(SUM(meta_horas_imp_area)::NUMERIC, 2)              AS meta_improd_area_h,
    ROUND((SUM(horas_improdutivas_area) * 100
           / NULLIF(SUM(virando_hrs)
                    + SUM(horas_improdutivas_area), 0))::NUMERIC, 2)
                                                             AS improd_pct,
    ROUND(SUM(horas_improdutivas_gerencial)::NUMERIC, 2)     AS improd_gerencial_h,
    ROUND((SUM(horas_improdutivas_gerencial) * 100
           / NULLIF(SUM(virando_hrs) + SUM(acerto_hrs)
                    + SUM(horas_improdutivas_area)
                    + SUM(horas_improdutivas_gerencial), 0))::NUMERIC, 2)
                                                             AS improd_ger_pct,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total,
    ROUND(SUM(tempo_total)::NUMERIC, 2)                      AS tempo_total
  FROM src
  WHERE item_key IS NOT NULL
  GROUP BY 1
  ORDER BY 1;
$$;


-- =========================================================
-- 7. printag_rank_motivos
-- + tipo_apontam / classificação na saída (o agente precisava
--   disso para dizer de quem é a responsabilidade da parada)
-- + filtro por tipo_acerto e por intervalo de datas.
-- =========================================================
DROP FUNCTION IF EXISTS printag_rank_motivos(INT, TEXT, INT[], INT[], INT[], TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS printag_rank_motivos(INT, TEXT, INT[], INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE);

CREATE FUNCTION printag_rank_motivos(
  p_ano          INT     DEFAULT NULL,
  p_escopo       TEXT    DEFAULT 'area',
  p_semanas      INT[]   DEFAULT NULL,
  p_meses        INT[]   DEFAULT NULL,
  p_maquinas     INT[]   DEFAULT NULL,
  p_tipos_acabam TEXT[]  DEFAULT NULL,
  p_operadores   TEXT[]  DEFAULT NULL,
  p_tipos_acerto TEXT[]  DEFAULT NULL,
  p_data_ini     DATE    DEFAULT NULL,
  p_data_fim     DATE    DEFAULT NULL
)
RETURNS TABLE (
  motivo             TEXT,
  classificacao_oee  TEXT,
  classificacao_perda TEXT,
  horas              NUMERIC,
  ocorrencias        BIGINT,
  pct_do_total       NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mv.apontamento                                          AS motivo,
    MAX(mv.classificacao_oee)                               AS classificacao_oee,
    MAX(mv.classificacao_perda)                             AS classificacao_perda,
    ROUND(SUM(mv.tempo_total)::NUMERIC, 2)                  AS horas,
    COUNT(*)::BIGINT                                        AS ocorrencias,
    ROUND((100.0 * SUM(mv.tempo_total)
           / NULLIF(SUM(SUM(mv.tempo_total)) OVER (), 0))::NUMERIC, 2)
                                                            AS pct_do_total
  FROM mv_base_apontamentos mv
  WHERE maquina_id IS NOT NULL
    AND mv.apontamento IS NOT NULL
    AND (
      CASE lower(COALESCE(p_escopo, 'area'))
        WHEN 'area'      THEN mv.classificacao_oee = 'Área'
        WHEN 'área'      THEN mv.classificacao_oee = 'Área'
        WHEN 'gerencial' THEN mv.classificacao_oee = 'Gerencial'
        ELSE TRUE
      END
    )
    AND (p_ano          IS NULL OR ano             =  p_ano)
    AND (p_semanas      IS NULL OR semana          = ANY(p_semanas))
    AND (p_meses        IS NULL OR mes             = ANY(p_meses))
    AND (p_maquinas     IS NULL OR maquina_id      = ANY(p_maquinas))
    AND (p_tipos_acabam IS NULL OR tipo_acabamento = ANY(p_tipos_acabam))
    AND (p_operadores   IS NULL OR operador        = ANY(p_operadores))
    AND (p_tipos_acerto IS NULL OR tipo_acerto     = ANY(p_tipos_acerto))
    AND (p_data_ini     IS NULL OR data           >= p_data_ini)
    AND (p_data_fim     IS NULL OR data           <= p_data_fim)
  GROUP BY mv.apontamento
  ORDER BY horas DESC NULLS LAST;
$$;


-- =========================================================
-- 8. printag_dados_faca
-- A tool que faltava para a planilha "Levantamento Metros
-- Lineares e Montagem": dimensões do cartucho + montagem,
-- já cruzadas com o desempenho real da OS.
-- =========================================================
DROP FUNCTION IF EXISTS printag_dados_faca(INT, TEXT[], TEXT[], INT[], INT, INT);

CREATE FUNCTION printag_dados_faca(
  p_ano      INT     DEFAULT NULL,
  p_os       TEXT[]  DEFAULT NULL,
  p_facas    TEXT[]  DEFAULT NULL,
  p_maquinas INT[]   DEFAULT NULL,
  p_montagem INT     DEFAULT NULL,
  p_limit    INT     DEFAULT 30
)
RETURNS TABLE (
  nro_os                   TEXT,
  numero_faca              TEXT,
  largura_cartucho_mm      NUMERIC,
  altura_cartucho_mm       NUMERIC,
  montagem                 INT,
  tipo_acabamento          TEXT,
  micro                    TEXT,
  nome_maquina             TEXT,
  nome_cliente             TEXT,
  titulo_produto           TEXT,
  acerto_hrs               NUMERIC,
  quantidade_acerto        BIGINT,
  tempo_medio_acerto_h     NUMERIC,
  virando_hrs              NUMERIC,
  vel_real_pech            NUMERIC,
  tiragem_media_pec_acerto NUMERIC,
  produzido_total          BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mv.os_corrida                                            AS nro_os,
    mv.numero_faca,
    mv.largura_cartucho                                      AS largura_cartucho_mm,
    mv.altura_cartucho                                       AS altura_cartucho_mm,
    mv.montagem,
    MAX(mv.tipo_acabamento)                                  AS tipo_acabamento,
    MAX(mv.micro)                                            AS micro,
    MAX(mv.nome_maquina)                                     AS nome_maquina,
    MAX(mv.nome_cliente)                                     AS nome_cliente,
    MAX(mv.titulo_produto)                                   AS titulo_produto,
    ROUND(SUM(acerto_hrs)::NUMERIC, 2)                       AS acerto_hrs,
    SUM(quantidade_acerto)::BIGINT                           AS quantidade_acerto,
    ROUND((SUM(acerto_hrs)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 2) AS tempo_medio_acerto_h,
    ROUND(SUM(virando_hrs)::NUMERIC, 2)                      AS virando_hrs,
    ROUND((SUM(produzido) FILTER (WHERE virando_hrs IS NOT NULL)
           / NULLIF(SUM(virando_hrs), 0))::NUMERIC, 2)       AS vel_real_pech,
    ROUND((SUM(produzido)
           / NULLIF(SUM(quantidade_acerto), 0))::NUMERIC, 0) AS tiragem_media_pec_acerto,
    SUM(produzido)::BIGINT                                   AS produzido_total
  FROM mv_base_apontamentos mv
  WHERE maquina_id IS NOT NULL
    AND mv.os_corrida IS NOT NULL
    AND (p_ano      IS NULL OR ano         =  p_ano)
    AND (p_os       IS NULL OR mv.os_corrida = ANY(p_os))
    AND (p_facas    IS NULL OR mv.numero_faca = ANY(p_facas))
    AND (p_maquinas IS NULL OR maquina_id  = ANY(p_maquinas))
    AND (p_montagem IS NULL OR mv.montagem =  p_montagem)
  GROUP BY mv.os_corrida, mv.numero_faca, mv.largura_cartucho,
           mv.altura_cartucho, mv.montagem
  ORDER BY SUM(produzido) DESC NULLS LAST
  LIMIT LEAST(COALESCE(p_limit, 30), 200);
$$;


-- =========================================================
-- 9. printag_filtros_agente
-- + tipos_acerto, montagens e a janela de datas com dado.
-- É o mapa que o agente usa antes de montar qualquer filtro.
-- =========================================================
DROP FUNCTION IF EXISTS printag_filtros_agente(INT);

CREATE FUNCTION printag_filtros_agente(p_ano INT DEFAULT NULL)
RETURNS TABLE (
  maquinas      JSON,
  operadores    JSON,
  tipos_acabam  JSON,
  tipos_acerto  JSON,
  montagens     JSON,
  semanas       JSON,
  meses         JSON,
  anos          JSON,
  janela_dados  JSON
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (SELECT json_agg(r ORDER BY r.area, r.nome)
     FROM (SELECT DISTINCT maquina_id AS id, nome_maquina AS nome, area
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS maquinas,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT operador AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND operador IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS operadores,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT tipo_acabamento AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND tipo_acabamento IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS tipos_acabam,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT tipo_acerto AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND tipo_acerto IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS tipos_acerto,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT montagem AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL AND montagem IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS montagens,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT semana AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS semanas,

    (SELECT json_agg(r ORDER BY r)
     FROM (SELECT DISTINCT mes AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL
             AND (p_ano IS NULL OR ano = p_ano)) r)          AS meses,

    (SELECT json_agg(r ORDER BY r DESC)
     FROM (SELECT DISTINCT ano AS r
           FROM mv_base_apontamentos
           WHERE maquina_id IS NOT NULL) r)                  AS anos,

    (SELECT json_build_object('data_min', MIN(data), 'data_max', MAX(data))
     FROM mv_base_apontamentos
     WHERE maquina_id IS NOT NULL
       AND (p_ano IS NULL OR ano = p_ano))                   AS janela_dados;
$$;


-- =========================================================
-- 10. printag_metas_agente
-- get_metas_acabamento apontava direto para a tabela, com os
-- percentuais em fração. Vira RPC, já em %, com a meta de
-- velocidade por família junto.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_metas_agente(p_maquinas TEXT[] DEFAULT NULL)
RETURNS TABLE (
  nome_maquina               TEXT,
  area                       TEXT,
  meta_acerto_mesma_faca_h   NUMERIC,
  meta_acerto_troca_faca_h   NUMERIC,
  meta_improd_area_pct       NUMERIC,
  meta_improd_gerencial_pct  NUMERIC,
  meta_velocidade_virando    NUMERIC,
  velocidade_mecanica        NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    m.nome_maquina,
    m.area,
    ROUND(mt.meta_acerto_mesma_faca::NUMERIC, 4),
    ROUND(mt.meta_acerto_troca_faca::NUMERIC, 4),
    ROUND((mt.meta_indisponibilidade_virando_area * 100)::NUMERIC, 2),
    ROUND((mt.meta_indisponibilidade_virando_gerencial * 100)::NUMERIC, 2),
    mt.meta_velocidade_virando::NUMERIC,
    m.velocidade::NUMERIC
  FROM printiag_maquinas m
  LEFT JOIN printiag_metas_maquinas mt ON mt.nome_maquina = m.nome_maquina
  WHERE (p_maquinas IS NULL OR m.nome_maquina = ANY(p_maquinas))
  ORDER BY m.area, m.nome_maquina;
$$;


-- ---- Permissões ----
GRANT EXECUTE ON FUNCTION printag_kpi_periodo(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE)         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_kpi_disponibilidade(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_kpi_yoy(TEXT, INT, INT[], INT[], TEXT[], TEXT[], TEXT[])                         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_rank_dimensao(TEXT, INT, INT[], INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_rank_motivos(INT, TEXT, INT[], INT[], INT[], TEXT[], TEXT[], TEXT[], DATE, DATE)  TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dados_faca(INT, TEXT[], TEXT[], INT[], INT, INT)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION printag_filtros_agente(INT)                                                              TO authenticated;
GRANT EXECUTE ON FUNCTION printag_metas_agente(TEXT[])                                                             TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- Conferência:
--   SELECT numero_faca, largura_cartucho, altura_cartucho, montagem
--     FROM mv_base_apontamentos WHERE numero_faca IS NOT NULL LIMIT 5;
--   SELECT periodo, periodo_label, tempo_medio_acerto_h
--     FROM printag_kpi_periodo('dia', 2026, NULL, NULL, NULL, NULL, NULL,
--                              DATE '2026-08-01', DATE '2026-08-07');
--   SELECT item, tempo_medio_acerto_h
--     FROM printag_rank_dimensao('tipo_acerto', 2026);
--   SELECT * FROM printag_dados_faca(2026, NULL, NULL, NULL, NULL, 5);
--   SELECT tipos_acerto, montagens, janela_dados FROM printag_filtros_agente(2026);
-- ---------------------------------------------------------------------


-- =======  DOWN  ========
-- Reaplicar 010 (MV), 016/023/029 (RPCs do agente) nesta ordem.

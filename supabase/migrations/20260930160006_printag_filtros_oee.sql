-- =============================================
-- Migration 006: Filtros Dinâmicos no OEE
-- Permite filtrar por semana, máquina, ano, tipo acabamento e operador
-- =============================================

-- 1. Atualizar a View de Apontamentos Classificados para incluir "tipo_acabamento" e "operador"
DROP VIEW IF EXISTS vw_oee_equipamento;
DROP VIEW IF EXISTS vw_apontamentos_classificado;

CREATE OR REPLACE VIEW vw_apontamentos_classificado AS
SELECT
  a.id,
  a.equipamento,
  COALESCE(e.area, 'Outros')                               AS area,
  e.velocidade_limite,
  a.inicio,
  a.fim,
  (a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE        AS dia,
  to_char(a.inicio AT TIME ZONE 'America/Sao_Paulo', 'IYYY-"W"IW') AS semana_iso,
  EXTRACT(week FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS semana,
  date_trunc('month', a.inicio AT TIME ZONE 'America/Sao_Paulo')::DATE AS mes,
  EXTRACT(year FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT AS ano,
  a.tipo_apontam,
  a.motivo,
  -- Lookup hierárquico
  COALESCE(cl_exact.classificacao_perda,
           cl_def.classificacao_perda,
           CASE a.tipo_apontam
             WHEN 'Produção' THEN 'Virando'
             WHEN 'Acerto'   THEN 'Acerto'
             ELSE 'Problema de Processo'
           END)                                            AS classificacao_perda,
  COALESCE(cl_exact.atuacao,
           cl_def.atuacao,
           CASE a.tipo_apontam
             WHEN 'Produção' THEN 'Virando'
             WHEN 'Acerto'   THEN 'Acerto'
             ELSE 'Área'
           END)                                            AS atuacao,
  a.duracao_min,
  a.produzido,
  a.nro_os,
  a.operador,
  pa.tipo_acabamento,
  a.atualizado_em
FROM apontamentos a
LEFT JOIN printiag_producao_acabamento pa ON pa.nro_os = a.nro_os
LEFT JOIN aux_equipamento e ON e.equipamento = a.equipamento
-- match exato por motivo
LEFT JOIN aux_classificacao_apontamento cl_exact
  ON cl_exact.tipo_apontam = a.tipo_apontam AND cl_exact.descricao = a.motivo
-- fallback: default do tipo
LEFT JOIN aux_classificacao_apontamento cl_def
  ON cl_def.tipo_apontam = a.tipo_apontam AND cl_def.descricao = '';

-- 2. Atualizar a View Agregada (adicionando tipo_acabamento e operador no GROUP BY)
CREATE OR REPLACE VIEW vw_oee_equipamento AS
WITH base AS (
  SELECT
    equipamento, area, velocidade_limite, dia, semana_iso, semana, mes, ano, operador, tipo_acabamento,
    classificacao_perda, atuacao, duracao_min, produzido, tipo_apontam, motivo
  FROM vw_apontamentos_classificado
),
por_equip AS (
  SELECT
    equipamento,
    area,
    operador,
    tipo_acabamento,
    MAX(velocidade_limite)  AS velocidade_limite,
    dia, semana_iso, semana, mes, ano,
    SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Virando')      AS min_virando,
    SUM(duracao_min) FILTER (WHERE classificacao_perda = 'Acerto')       AS min_acerto,
    SUM(duracao_min) FILTER (WHERE atuacao = 'Área' AND classificacao_perda <> 'Virando') AS min_improd_area,
    SUM(duracao_min) FILTER (WHERE atuacao = 'Gerencial')                AS min_improd_ger,
    SUM(produzido)   FILTER (WHERE classificacao_perda = 'Virando')      AS qtd_produzido,
    COUNT(*) FILTER (WHERE tipo_apontam = 'Acerto')                      AS qtd_acertos,
    SUM(duracao_min)                                                      AS min_total
  FROM base
  GROUP BY equipamento, area, operador, tipo_acabamento, dia, semana_iso, semana, mes, ano
)
SELECT
  pe.*,
  ROUND(CASE WHEN COALESCE(pe.min_virando,0) > 0 THEN pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0) ELSE 0 END, 2) AS vel_media_virando,
  ROUND(CASE WHEN COALESCE(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) > 0 THEN pe.min_virando / NULLIF(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) * 100 ELSE 0 END, 2) AS disp_operacional,
  ROUND(CASE WHEN COALESCE(pe.min_total, 0) > 0 THEN pe.min_virando / NULLIF(pe.min_total, 0) * 100 ELSE 0 END, 2) AS disp_gerencial,
  ROUND(CASE WHEN COALESCE(pe.velocidade_limite, 0) > 0 AND COALESCE(pe.min_virando, 0) > 0 THEN (pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0)) / pe.velocidade_limite * 100 ELSE 0 END, 2) AS desempenho,
  ROUND(CASE WHEN COALESCE(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0) > 0 AND COALESCE(pe.velocidade_limite, 0) > 0 AND COALESCE(pe.min_virando, 0) > 0 THEN (pe.min_virando / NULLIF(pe.min_virando + pe.min_acerto + pe.min_improd_area, 0)) * ((pe.qtd_produzido::NUMERIC / (pe.min_virando / 60.0)) / pe.velocidade_limite) * 100 ELSE 0 END, 2) AS oee_operacional,
  ROUND(CASE WHEN COALESCE(pe.qtd_acertos, 0) > 0 THEN (pe.min_acerto / pe.qtd_acertos) / 60.0 ELSE 0 END, 3) AS tempo_medio_acerto_h,
  ROUND(CASE WHEN COALESCE(pe.min_total, 0) > 0 THEN (pe.min_total - COALESCE(pe.min_virando, 0)) / pe.min_total * 100 ELSE 0 END, 2) AS indice_improdutivos
FROM por_equip pe;


-- 3. Função Auxiliar: Filtrar Lista Única de Opções para o HTML Dropdowns
CREATE OR REPLACE FUNCTION printag_oee_filtros_disponiveis()
RETURNS json AS $$
DECLARE v_res json;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  SELECT json_build_object(
    'equipamentos', (SELECT json_agg(DISTINCT equipamento) FROM apontamentos WHERE equipamento IS NOT NULL AND equipamento <> ''),
    'operadores', (SELECT json_agg(DISTINCT operador) FROM apontamentos WHERE operador IS NOT NULL AND operador <> ''),
    'tipos_acabamento', (SELECT json_agg(DISTINCT tipo_acabamento) FROM printiag_producao_acabamento WHERE tipo_acabamento IS NOT NULL AND tipo_acabamento <> ''),
    'anos', (SELECT json_agg(DISTINCT EXTRACT(year FROM inicio AT TIME ZONE 'America/Sao_Paulo')::INT) FROM apontamentos WHERE inicio IS NOT NULL),
    'semanas', (SELECT json_agg(DISTINCT EXTRACT(week FROM inicio AT TIME ZONE 'America/Sao_Paulo')::INT) FROM apontamentos WHERE inicio IS NOT NULL)
  ) INTO v_res;
  RETURN v_res;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Atualizar as RPCs do Dashboard com os novos Filtros (Opcionais)
-- Removendo funções antigas se houver conflito de assinatura (boa prática em dev)
DROP FUNCTION IF EXISTS printag_oee_kpis(INT);
DROP FUNCTION IF EXISTS printag_oee_kpis(INT, INT, TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_kpis(
  p_dias INT DEFAULT 30,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS json AS $$
DECLARE v_res json;
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;

  WITH agg AS (
    SELECT
      SUM(min_virando)      AS min_virando,
      SUM(min_acerto)       AS min_acerto,
      SUM(min_improd_area)  AS min_improd_area,
      SUM(min_improd_ger)   AS min_improd_ger,
      SUM(min_total)        AS min_total,
      SUM(qtd_produzido)    AS qtd_produzido,
      SUM(qtd_acertos)      AS qtd_acertos,
      -- Prod teórica (limite)
      SUM(CASE WHEN velocidade_limite > 0 THEN min_virando / 60.0 * velocidade_limite ELSE 0 END) AS prod_teorica
    FROM vw_oee_equipamento o
    WHERE o.dia >= CURRENT_DATE - p_dias
      AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR o.semana = ANY(p_semanas))
      AND (p_equipamento IS NULL OR p_equipamento = '' OR o.equipamento = p_equipamento)
      AND (p_ano IS NULL OR o.ano = p_ano)
      AND (p_operador IS NULL OR p_operador = '' OR o.operador = p_operador)
      AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR o.tipo_acabamento = p_tipo_acabamento)
  )
  SELECT row_to_json(t) INTO v_res
  FROM (
    SELECT
      COALESCE(ROUND(CASE WHEN min_virando + min_acerto + min_improd_area > 0 
                    THEN (min_virando / (min_virando + min_acerto + min_improd_area)) * (qtd_produzido / NULLIF(prod_teorica, 0)) * 100
                    ELSE 0 END, 2), 0) AS oee_operacional,
      COALESCE(ROUND(qtd_produzido, 0), 0) AS qtd_produzido,
      COALESCE(ROUND(CASE WHEN min_virando + min_acerto + min_improd_area > 0 THEN (min_virando / (min_virando + min_acerto + min_improd_area)) * 100 ELSE 0 END, 2), 0) AS disp_operacional,
      COALESCE(ROUND(min_virando, 2), 0) AS min_virando,
      COALESCE(ROUND(CASE WHEN prod_teorica > 0 THEN (qtd_produzido / prod_teorica) * 100 ELSE 0 END, 2), 0) AS desempenho,
      COALESCE(ROUND(CASE WHEN min_virando > 0 THEN qtd_produzido / (min_virando/60.0) ELSE 0 END, 2), 0) AS vel_media_virando,
      COALESCE(ROUND(CASE WHEN qtd_acertos > 0 THEN (min_acerto / qtd_acertos) / 60.0 ELSE 0 END, 3), 0) AS tempo_medio_acerto_h,
      COALESCE(ROUND(CASE WHEN min_total > 0 THEN (min_total - min_virando) / min_total * 100 ELSE 0 END, 2), 0) AS indice_improdutivos,
      COALESCE(ROUND(min_acerto, 2), 0) AS min_acerto
    FROM agg
  ) t;
  RETURN COALESCE(v_res, '{}'::json);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS printag_oee_por_equipamento(INT);
DROP FUNCTION IF EXISTS printag_oee_por_equipamento(INT, INT, TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_por_equipamento(
  p_dias INT DEFAULT 30,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS TABLE (
  equipamento TEXT, area TEXT, oee_operacional NUMERIC, disp_operacional NUMERIC,
  desempenho NUMERIC, vel_media_virando NUMERIC, meta_velocidade NUMERIC, tempo_medio_acerto_h NUMERIC
) AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN QUERY
  WITH agg AS (
    SELECT
      o.equipamento,
      MAX(o.area) AS area,
      SUM(o.min_virando)     AS min_virando,
      SUM(o.min_acerto)      AS min_acerto,
      SUM(o.min_improd_area) AS min_improd_area,
      SUM(o.qtd_produzido)   AS qtd_produzido,
      SUM(o.qtd_acertos)     AS qtd_acertos,
      MAX(o.velocidade_limite) AS max_velocidade_limite,
      SUM(CASE WHEN o.velocidade_limite > 0 THEN o.min_virando / 60.0 * o.velocidade_limite ELSE 0 END) AS prod_teorica
    FROM vw_oee_equipamento o
    WHERE o.dia >= CURRENT_DATE - p_dias
      AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR o.semana = ANY(p_semanas))
      AND (p_equipamento IS NULL OR p_equipamento = '' OR o.equipamento = p_equipamento)
      AND (p_ano IS NULL OR o.ano = p_ano)
      AND (p_operador IS NULL OR p_operador = '' OR o.operador = p_operador)
      AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR o.tipo_acabamento = p_tipo_acabamento)
    GROUP BY o.equipamento
  )
  SELECT
    a.equipamento,
    a.area,
    ROUND(CASE WHEN a.min_virando + a.min_acerto + a.min_improd_area > 0 THEN (a.min_virando / (a.min_virando + a.min_acerto + a.min_improd_area)) * (a.qtd_produzido / NULLIF(a.prod_teorica, 0)) * 100 ELSE 0 END, 2) AS oee_operacional,
    ROUND(CASE WHEN a.min_virando + a.min_acerto + a.min_improd_area > 0 THEN (a.min_virando / (a.min_virando + a.min_acerto + a.min_improd_area)) * 100 ELSE 0 END, 2) AS disp_operacional,
    ROUND(CASE WHEN a.prod_teorica > 0 THEN (a.qtd_produzido / a.prod_teorica) * 100 ELSE 0 END, 2) AS desempenho,
    ROUND(CASE WHEN a.min_virando > 0 THEN a.qtd_produzido / (a.min_virando/60.0) ELSE 0 END, 2) AS vel_media_virando,
    ROUND(COALESCE(a.max_velocidade_limite, 0), 2) AS meta_velocidade,
    ROUND(CASE WHEN a.qtd_acertos > 0 THEN (a.min_acerto / a.qtd_acertos) / 60.0 ELSE 0 END, 3) AS tempo_medio_acerto_h
  FROM agg a
  ORDER BY oee_operacional DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS printag_oee_por_semana(INT, INT[], TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_por_semana(
  p_dias INT DEFAULT 30,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS TABLE (
  semana INT, oee_operacional NUMERIC, disp_operacional NUMERIC,
  desempenho NUMERIC, vel_media_virando NUMERIC, meta_velocidade NUMERIC, tempo_medio_acerto_h NUMERIC, indice_improdutivos NUMERIC, velocidade_media NUMERIC
) AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN QUERY
  WITH agg AS (
    SELECT
      o.semana,
      SUM(o.min_virando)     AS min_virando,
      SUM(o.min_acerto)      AS min_acerto,
      SUM(o.min_improd_area) AS min_improd_area,
      SUM(o.min_total)       AS min_total,
      SUM(o.qtd_produzido)   AS qtd_produzido,
      SUM(o.qtd_acertos)     AS qtd_acertos,
      SUM(CASE WHEN o.velocidade_limite > 0 THEN o.min_virando / 60.0 * o.velocidade_limite ELSE 0 END) AS prod_teorica,
      MAX(o.velocidade_limite) AS velocidade_limite
    FROM vw_oee_equipamento o
    WHERE o.dia >= CURRENT_DATE - p_dias
      AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR o.semana = ANY(p_semanas))
      AND (p_equipamento IS NULL OR p_equipamento = '' OR o.equipamento = p_equipamento)
      AND (p_ano IS NULL OR o.ano = p_ano)
      AND (p_operador IS NULL OR p_operador = '' OR o.operador = p_operador)
      AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR o.tipo_acabamento = p_tipo_acabamento)
    GROUP BY o.semana
  )
  SELECT
    agg.semana,
    COALESCE(ROUND(CASE WHEN min_virando + min_acerto + min_improd_area > 0 AND prod_teorica > 0 AND min_virando > 0 THEN (min_virando / (min_virando + min_acerto + min_improd_area)) * ((qtd_produzido / (min_virando/60.0)) / (prod_teorica / (min_virando/60.0))) * 100 ELSE 0 END, 2), 0) AS oee_operacional,
    COALESCE(ROUND(CASE WHEN min_virando + min_acerto + min_improd_area > 0 THEN (min_virando / (min_virando + min_acerto + min_improd_area)) * 100 ELSE 0 END, 2), 0) AS disp_operacional,
    COALESCE(ROUND(CASE WHEN prod_teorica > 0 THEN (qtd_produzido / prod_teorica) * 100 ELSE 0 END, 2), 0) AS desempenho,
    COALESCE(ROUND(CASE WHEN min_virando > 0 THEN qtd_produzido / (min_virando/60.0) ELSE 0 END, 2), 0) AS vel_media_virando,
    COALESCE(ROUND(velocidade_limite, 2), 0) AS meta_velocidade,
    COALESCE(ROUND(CASE WHEN qtd_acertos > 0 THEN (min_acerto / qtd_acertos) / 60.0 ELSE 0 END, 3), 0) AS tempo_medio_acerto_h,
    COALESCE(ROUND(CASE WHEN min_total > 0 THEN (min_total - min_virando) / min_total * 100 ELSE 0 END, 2), 0) AS indice_improdutivos,
    COALESCE(ROUND(CASE WHEN min_virando > 0 THEN qtd_produzido / (min_virando/60.0) ELSE 0 END, 2), 0) AS velocidade_media
  FROM agg
  ORDER BY agg.semana ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS printag_oee_pareto_improdutivos(INT, INT);
DROP FUNCTION IF EXISTS printag_oee_pareto_improdutivos(INT, INT, INT, TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_pareto_improdutivos(
  p_dias INT DEFAULT 30,
  p_top INT DEFAULT 10,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS TABLE (classificacao_perda TEXT, horas_parado NUMERIC, pct_acumulado NUMERIC) AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN QUERY
  WITH perdas AS (
    SELECT
      a.classificacao_perda,
      SUM(a.duracao_min) / 60.0 AS calc_horas
    FROM vw_apontamentos_classificado a
    WHERE a.dia >= CURRENT_DATE - p_dias
      AND a.classificacao_perda NOT IN ('Virando', 'Acerto', 'Operacional Planejado')
      AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR a.semana = ANY(p_semanas))
      AND (p_equipamento IS NULL OR p_equipamento = '' OR a.equipamento = p_equipamento)
      AND (p_ano IS NULL OR a.ano = p_ano)
      AND (p_operador IS NULL OR p_operador = '' OR a.operador = p_operador)
      AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR a.tipo_acabamento = p_tipo_acabamento)
    GROUP BY a.classificacao_perda
    ORDER BY calc_horas DESC
    LIMIT p_top
  ),
  totais AS (SELECT SUM(calc_horas) AS total FROM perdas)
  SELECT
    p.classificacao_perda,
    ROUND(p.calc_horas, 2),
    ROUND((SUM(p.calc_horas) OVER (ORDER BY p.calc_horas DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(t.total, 0) * 100), 2)
  FROM perdas p CROSS JOIN totais t
  ORDER BY p.calc_horas DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS printag_oee_producao_por_tipo(INT);
DROP FUNCTION IF EXISTS printag_oee_producao_por_tipo(INT, INT, TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_producao_por_tipo(
  p_dias INT DEFAULT 30,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS TABLE (tipo_acabamento TEXT, equipamento_plan TEXT, qtd_produzida NUMERIC) AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN QUERY
  SELECT
    COALESCE(pa.tipo_acabamento, 'Sem Tipo') AS tipo_acabamento,
    COALESCE(pa.equipamento_plan, a.equipamento, 'Não Definido') AS equipamento_plan,
    ROUND(SUM(a.produzido), 2) AS qtd_produzida
  FROM apontamentos a
  LEFT JOIN printiag_producao_acabamento pa ON pa.nro_os = a.nro_os
  WHERE a.inicio::DATE >= CURRENT_DATE - p_dias
    AND a.produzido > 0
    AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR EXTRACT(week FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT = ANY(p_semanas))
    AND (p_equipamento IS NULL OR p_equipamento = '' OR a.equipamento = p_equipamento)
    AND (p_ano IS NULL OR EXTRACT(year FROM a.inicio AT TIME ZONE 'America/Sao_Paulo')::INT = p_ano)
    AND (p_operador IS NULL OR p_operador = '' OR a.operador = p_operador)
    AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR pa.tipo_acabamento = p_tipo_acabamento)
  GROUP BY COALESCE(pa.tipo_acabamento, 'Sem Tipo'), COALESCE(pa.equipamento_plan, a.equipamento, 'Não Definido')
  ORDER BY qtd_produzida DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS printag_oee_acerto_por_tipo(INT);
DROP FUNCTION IF EXISTS printag_oee_acerto_por_tipo(INT, INT[], TEXT, INT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION printag_oee_acerto_por_tipo(
  p_dias INT DEFAULT 30,
  p_semanas INT[] DEFAULT NULL,
  p_equipamento TEXT DEFAULT NULL,
  p_ano INT DEFAULT NULL,
  p_operador TEXT DEFAULT NULL,
  p_tipo_acabamento TEXT DEFAULT NULL
) RETURNS TABLE (tipo_acabamento TEXT, tempo_medio_acerto_h NUMERIC) AS $$
BEGIN
  IF NOT printag_is_member() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  RETURN QUERY
  SELECT
    COALESCE(a.tipo_acabamento, 'Sem Tipo') AS tipo_acabamento,
    ROUND(CASE WHEN COUNT(*) > 0 THEN SUM(a.duracao_min) / COUNT(*) / 60.0 ELSE 0 END, 3) AS tempo_medio_acerto_h
  FROM vw_apontamentos_classificado a
  WHERE a.dia >= CURRENT_DATE - p_dias
    AND a.classificacao_perda = 'Acerto'
    AND (p_semanas IS NULL OR array_length(p_semanas, 1) IS NULL OR a.semana = ANY(p_semanas))
    AND (p_equipamento IS NULL OR p_equipamento = '' OR a.equipamento = p_equipamento)
    AND (p_ano IS NULL OR a.ano = p_ano)
    AND (p_operador IS NULL OR p_operador = '' OR a.operador = p_operador)
    AND (p_tipo_acabamento IS NULL OR p_tipo_acabamento = '' OR a.tipo_acabamento = p_tipo_acabamento)
  GROUP BY COALESCE(a.tipo_acabamento, 'Sem Tipo')
  ORDER BY tempo_medio_acerto_h DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. Recriar GRANTs
GRANT EXECUTE ON FUNCTION printag_oee_filtros_disponiveis() TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_kpis(INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_por_equipamento(INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_por_semana(INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_pareto_improdutivos(INT, INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_producao_por_tipo(INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_oee_acerto_por_tipo(INT, INT[], TEXT, INT, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =============================================
-- PrintAG — 003: Funções RPC do Dashboard de Produção
-- Expõe os indicadores agregados das tabelas de produção para o front.
-- Restrito a membros do tenant 'printag' (admin OU visualizador).
-- Versões finais já com filtro de período (p_dias).
-- =============================================

-- =======  UP  ========

-- ---------- Helper: printag_is_member ----------
CREATE OR REPLACE FUNCTION printag_is_member()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_company TEXT;
BEGIN
  SELECT raw_user_meta_data->>'company_name'
    INTO v_company
    FROM auth.users
   WHERE id = auth.uid();
  RETURN v_company = 'printag';
END;
$$;

-- ---------- printag_dashboard_kpis(p_dias) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_kpis(p_dias INT DEFAULT 30)
RETURNS JSON
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_since TIMESTAMPTZ;
  v JSON;
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  v_since := (CURRENT_DATE - (GREATEST(p_dias, 1) || ' days')::INTERVAL);

  WITH ap AS (
    SELECT * FROM apontamentos WHERE inicio >= v_since
  ),
  os_periodo AS (
    SELECT DISTINCT os.nro_os, os.repetiu_erro
      FROM ordens_servico os
      JOIN ap ON ap.nro_os = os.nro_os
  )
  SELECT json_build_object(
    'total_os',           (SELECT COUNT(*) FROM os_periodo),
    'os_com_refugo',      (SELECT COUNT(*) FROM os_periodo WHERE repetiu_erro = TRUE),
    'pct_refugo',         (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE repetiu_erro)
                                        / NULLIF(COUNT(*), 0), 2)
                             FROM os_periodo),
    'total_apontamentos', (SELECT COUNT(*) FROM ap),
    'qtd_equipamentos',   (SELECT COUNT(DISTINCT equipamento) FROM ap),
    'produzido_total',    (SELECT COALESCE(SUM(produzido), 0) FROM ap),
    'minutos_producao',   (SELECT COALESCE(ROUND(SUM(duracao_min)::NUMERIC, 0), 0)
                             FROM ap WHERE tipo_apontam = 'Produção'),
    'minutos_ocioso',     (SELECT COALESCE(ROUND(SUM(duracao_min)::NUMERIC, 0), 0)
                             FROM ap WHERE tipo_apontam = 'Ocioso'),
    'pct_utilizacao',     (SELECT CASE
                              WHEN COALESCE(SUM(duracao_min), 0) = 0 THEN 0
                              ELSE ROUND(100.0 * SUM(duracao_min) FILTER (WHERE tipo_apontam = 'Produção')
                                              / SUM(duracao_min), 2)
                            END
                             FROM ap),
    'p_dias',             p_dias,
    'desde',              v_since
  ) INTO v;

  RETURN v;
END;
$$;

-- ---------- printag_dashboard_status_os(p_limit) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_status_os(p_limit INT DEFAULT 50)
RETURNS TABLE(
  nro_os               TEXT,
  titulo               TEXT,
  nome_cliente         TEXT,
  setor                TEXT,
  tipo_servico         TEXT,
  quantidade           INTEGER,
  produzido_total      BIGINT,
  pct_concluido        NUMERIC,
  minutos_producao     NUMERIC,
  minutos_ocioso       NUMERIC,
  qtd_equipamentos     BIGINT,
  repetiu_erro         BOOLEAN,
  ultimo_apontamento   TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
    SELECT
      v.nro_os, v.titulo, v.nome_cliente, v.setor, v.tipo_servico,
      v.quantidade, v.produzido_total, v.pct_concluido,
      v.minutos_producao, v.minutos_ocioso, v.qtd_equipamentos,
      v.repetiu_erro, v.ultimo_apontamento
    FROM vw_status_os v
    ORDER BY v.ultimo_apontamento DESC NULLS LAST
    LIMIT GREATEST(p_limit, 1);
END;
$$;

-- ---------- printag_dashboard_producao_diaria(p_dias) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_producao_diaria(p_dias INT DEFAULT 30)
RETURNS TABLE(
  dia              DATE,
  produzido        BIGINT,
  minutos_producao NUMERIC,
  minutos_ocioso   NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
    SELECT
      d.dia,
      SUM(d.produzido)::BIGINT                                AS produzido,
      ROUND(COALESCE(SUM(d.minutos_producao), 0)::NUMERIC, 2) AS minutos_producao,
      ROUND(COALESCE(SUM(d.minutos_ocioso),   0)::NUMERIC, 2) AS minutos_ocioso
    FROM vw_producao_diaria d
    WHERE d.dia >= (CURRENT_DATE - (GREATEST(p_dias, 1) || ' days')::INTERVAL)
    GROUP BY d.dia
    ORDER BY d.dia;
END;
$$;

-- ---------- printag_dashboard_paradas_maquina(p_dias) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_paradas_maquina(p_dias INT DEFAULT 30)
RETURNS TABLE(
  equipamento    TEXT,
  motivo         TEXT,
  qtd_paradas    BIGINT,
  minutos_parado NUMERIC,
  horas_parado   NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  v_since := (CURRENT_DATE - (GREATEST(p_dias, 1) || ' days')::INTERVAL);

  RETURN QUERY
    SELECT
      a.equipamento,
      COALESCE(a.motivo, 'Não informado')::TEXT                          AS motivo,
      COUNT(*)::BIGINT                                                   AS qtd_paradas,
      ROUND(COALESCE(SUM(a.duracao_min), 0)::NUMERIC, 2)                 AS minutos_parado,
      ROUND(COALESCE(SUM(a.duracao_min), 0)::NUMERIC / 60.0, 2)          AS horas_parado
    FROM apontamentos a
   WHERE a.tipo_apontam = 'Ocioso'
     AND a.inicio >= v_since
   GROUP BY a.equipamento, COALESCE(a.motivo, 'Não informado')
   ORDER BY minutos_parado DESC NULLS LAST;
END;
$$;

-- ---------- printag_dashboard_refugo_por_setor(p_dias) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_refugo_por_setor(p_dias INT DEFAULT 30)
RETURNS TABLE(
  setor         TEXT,
  total_os      BIGINT,
  os_com_refugo BIGINT,
  pct_refugo    NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  v_since := (CURRENT_DATE - (GREATEST(p_dias, 1) || ' days')::INTERVAL);

  RETURN QUERY
    WITH os_periodo AS (
      SELECT DISTINCT os.nro_os, os.setor, os.repetiu_erro
        FROM ordens_servico os
        JOIN apontamentos a ON a.nro_os = os.nro_os
       WHERE a.inicio >= v_since
    )
    SELECT
      COALESCE(p.setor, 'Não informado')::TEXT                            AS setor,
      COUNT(*)::BIGINT                                                    AS total_os,
      COUNT(*) FILTER (WHERE p.repetiu_erro)::BIGINT                      AS os_com_refugo,
      ROUND(100.0 * COUNT(*) FILTER (WHERE p.repetiu_erro)
                  / NULLIF(COUNT(*), 0), 2)                               AS pct_refugo
    FROM os_periodo p
    GROUP BY COALESCE(p.setor, 'Não informado')
    ORDER BY pct_refugo DESC NULLS LAST;
END;
$$;

-- ---------- printag_dashboard_equipamentos(p_dias) ----------
CREATE OR REPLACE FUNCTION printag_dashboard_equipamentos(p_dias INT DEFAULT 30)
RETURNS TABLE(
  equipamento      TEXT,
  produzido        BIGINT,
  minutos_producao NUMERIC,
  minutos_ocioso   NUMERIC,
  pct_utilizacao   NUMERIC
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_since TIMESTAMPTZ;
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  v_since := (CURRENT_DATE - (GREATEST(p_dias, 1) || ' days')::INTERVAL);

  RETURN QUERY
    SELECT
      a.equipamento,
      COALESCE(SUM(a.produzido), 0)::BIGINT                                                              AS produzido,
      ROUND(COALESCE(SUM(a.duracao_min) FILTER (WHERE a.tipo_apontam = 'Produção'), 0)::NUMERIC, 2)      AS minutos_producao,
      ROUND(COALESCE(SUM(a.duracao_min) FILTER (WHERE a.tipo_apontam = 'Ocioso'),   0)::NUMERIC, 2)      AS minutos_ocioso,
      CASE
        WHEN COALESCE(SUM(a.duracao_min), 0) = 0 THEN 0
        ELSE ROUND(100.0 * SUM(a.duracao_min) FILTER (WHERE a.tipo_apontam = 'Produção')
                         / SUM(a.duracao_min), 2)
      END                                                                                                AS pct_utilizacao
    FROM apontamentos a
   WHERE a.inicio >= v_since
   GROUP BY a.equipamento
   ORDER BY produzido DESC, a.equipamento;
END;
$$;

-- ---------- GRANTs ----------
GRANT EXECUTE ON FUNCTION printag_is_member()                            TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_kpis(INT)                    TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_status_os(INT)               TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_producao_diaria(INT)         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_paradas_maquina(INT)         TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_refugo_por_setor(INT)        TO authenticated;
GRANT EXECUTE ON FUNCTION printag_dashboard_equipamentos(INT)            TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_equipamentos(INT)            FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_refugo_por_setor(INT)        FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_paradas_maquina(INT)         FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_producao_diaria(INT)         FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_status_os(INT)               FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_dashboard_kpis(INT)                    FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_is_member()                            FROM authenticated;
-- DROP FUNCTION IF EXISTS printag_dashboard_equipamentos(INT);
-- DROP FUNCTION IF EXISTS printag_dashboard_refugo_por_setor(INT);
-- DROP FUNCTION IF EXISTS printag_dashboard_paradas_maquina(INT);
-- DROP FUNCTION IF EXISTS printag_dashboard_producao_diaria(INT);
-- DROP FUNCTION IF EXISTS printag_dashboard_status_os(INT);
-- DROP FUNCTION IF EXISTS printag_dashboard_kpis(INT);
-- DROP FUNCTION IF EXISTS printag_is_member();
-- NOTIFY pgrst, 'reload schema';

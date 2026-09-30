-- =========================================================
-- PrintAG — 021: CRUD de printiag_classificacao
--
-- Tela de administração do de-para chave → classificação OEE.
-- A tabela é lida pela mv_base_apontamentos via
--   LEFT JOIN LATERAL ... WHERE chave_norm = a.chave ORDER BY id LIMIT 1
-- então qualquer alteração só aparece nos dashboards após REFRESH.
--
-- Os valores de classificacao_perda / atuacao / nivel_atuacao são usados
-- como literais em 010, 011, 014 e 015. Um valor fora do domínio (ou com
-- acentuação diferente) zera silenciosamente um bucket de horas inteiro,
-- por isso a validação é feita aqui e não só no front.
-- =========================================================

-- =======  UP  ========

-- =========================================================
-- 0. printag_valida_dominio_classificacao
-- Domínios extraídos do seed de 008. A acentuação precisa bater exatamente
-- com os literais usados nos CASE WHEN da mv_base_apontamentos.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_valida_dominio_classificacao(
  p_classificacao_perda TEXT,
  p_atuacao             TEXT,
  p_nivel_atuacao       TEXT
)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p_classificacao_perda IS NULL OR p_classificacao_perda NOT IN (
    'Virando', 'Acerto', 'Sem Apontamento', 'Sem Serviço', 'Sem Tripulação',
    'Operacional Planejado', 'Manutenção Preventiva', 'Manutenção Corretiva',
    'Problema de Processo', 'Aguardando'
  ) THEN
    RAISE EXCEPTION 'Classificação de perda inválida: %', COALESCE(p_classificacao_perda, '(vazio)');
  END IF;

  IF p_atuacao IS NULL OR p_atuacao NOT IN (
    'Virando', 'Acerto', 'Área', 'Gerencial', 'Sem Apontamento'
  ) THEN
    RAISE EXCEPTION 'Atuação inválida: %', COALESCE(p_atuacao, '(vazio)');
  END IF;

  IF p_nivel_atuacao IS NOT NULL AND trim(p_nivel_atuacao) <> ''
     AND p_nivel_atuacao NOT IN ('Gerencial', 'Liderança', 'Operacional') THEN
    RAISE EXCEPTION 'Nível de atuação inválido: %', p_nivel_atuacao;
  END IF;
END;
$$;

-- =========================================================
-- 1. printag_get_classificacoes
-- Lista com uso real (qtd de apontamentos) e alerta de colisão de chave_norm.
-- =========================================================
DROP FUNCTION IF EXISTS printag_get_classificacoes();

CREATE OR REPLACE FUNCTION printag_get_classificacoes()
RETURNS TABLE (
  id                  INT,
  chave               TEXT,
  tipo_apontam        TEXT,
  motivo              TEXT,
  classificacao_perda TEXT,
  atuacao             TEXT,
  nivel_atuacao       TEXT,
  qtd_apontamentos    BIGINT,
  chave_duplicada     BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.chave,
    c.tipo_apontam,
    c.motivo,
    c.classificacao_perda,
    c.atuacao,
    c.nivel_atuacao,
    COALESCE(u.qtd, 0)::BIGINT,
    -- Colisão: outra linha normaliza para o mesmo chave_norm. Na MV vence a de menor id.
    (COUNT(*) OVER (PARTITION BY c.chave_norm) > 1)
  FROM printiag_classificacao c
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS qtd
    FROM printag_apontamentos a
    WHERE a.chave = c.chave_norm
  ) u ON TRUE
  ORDER BY c.tipo_apontam, c.motivo;
END;
$$;

-- =========================================================
-- 2. printag_insert_classificacao
-- =========================================================
DROP FUNCTION IF EXISTS printag_insert_classificacao(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION printag_insert_classificacao(
  p_chave               TEXT,
  p_tipo_apontam        TEXT,
  p_motivo              TEXT,
  p_classificacao_perda TEXT,
  p_atuacao             TEXT,
  p_nivel_atuacao       TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id    INT;
  v_chave TEXT := trim(COALESCE(p_chave, ''));
  v_tipo  TEXT := trim(COALESCE(p_tipo_apontam, ''));
  v_mot   TEXT := trim(COALESCE(p_motivo, ''));
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem editar as classificações.';
  END IF;

  IF v_chave = '' THEN
    RAISE EXCEPTION 'A chave é obrigatória.';
  END IF;
  IF v_tipo = '' THEN
    RAISE EXCEPTION 'O tipo de apontamento é obrigatório.';
  END IF;

  PERFORM printag_valida_dominio_classificacao(p_classificacao_perda, p_atuacao, p_nivel_atuacao);

  IF EXISTS (SELECT 1 FROM printiag_classificacao WHERE chave_norm = norm(v_chave)) THEN
    RAISE EXCEPTION 'Já existe uma classificação equivalente a "%" (comparação ignora acentos e maiúsculas).', v_chave;
  END IF;

  INSERT INTO printiag_classificacao
    (chave, tipo_apontam, motivo, classificacao_perda, atuacao, nivel_atuacao)
  VALUES
    (v_chave, v_tipo, v_mot, p_classificacao_perda, p_atuacao, NULLIF(trim(COALESCE(p_nivel_atuacao, '')), ''))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- =========================================================
-- 3. printag_update_classificacao
-- Só os campos de classificação. chave/tipo/motivo são imutáveis porque
-- alterá-los muda chave_norm e quebra o join com printag_apontamentos.chave.
-- =========================================================
DROP FUNCTION IF EXISTS printag_update_classificacao(INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION printag_update_classificacao(
  p_id                  INT,
  p_classificacao_perda TEXT,
  p_atuacao             TEXT,
  p_nivel_atuacao       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem editar as classificações.';
  END IF;

  PERFORM printag_valida_dominio_classificacao(p_classificacao_perda, p_atuacao, p_nivel_atuacao);

  UPDATE printiag_classificacao
  SET classificacao_perda = p_classificacao_perda,
      atuacao             = p_atuacao,
      nivel_atuacao       = NULLIF(trim(COALESCE(p_nivel_atuacao, '')), '')
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Classificação % não encontrada.', p_id;
  END IF;
END;
$$;

-- =========================================================
-- 4. printag_delete_classificacao
-- Bloqueia a exclusão quando há apontamentos usando a chave.
-- =========================================================
DROP FUNCTION IF EXISTS printag_delete_classificacao(INT);

CREATE OR REPLACE FUNCTION printag_delete_classificacao(p_id INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_chave_norm TEXT;
  v_qtd        BIGINT;
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem editar as classificações.';
  END IF;

  SELECT chave_norm INTO v_chave_norm
  FROM printiag_classificacao
  WHERE id = p_id;

  IF v_chave_norm IS NULL THEN
    RAISE EXCEPTION 'Classificação % não encontrada.', p_id;
  END IF;

  SELECT COUNT(*) INTO v_qtd
  FROM printag_apontamentos
  WHERE chave = v_chave_norm;

  IF v_qtd > 0 THEN
    RAISE EXCEPTION
      'Não é possível excluir: % apontamento(s) usam esta chave. Reclassifique-os antes.', v_qtd;
  END IF;

  DELETE FROM printiag_classificacao WHERE id = p_id;
END;
$$;

-- =========================================================
-- 5. printag_refresh_base
-- Reescrita para exigir admin. Antes era SECURITY DEFINER sem checagem
-- alguma e sem GRANT explícito, ou seja, executável pela role anon.
-- =========================================================
CREATE OR REPLACE FUNCTION printag_refresh_base()
  RETURNS VOID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  SET statement_timeout = 0
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem atualizar a base.';
  END IF;

  IF (SELECT ispopulated FROM pg_matviews WHERE matviewname = 'mv_base_apontamentos') THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_base_apontamentos;
  ELSE
    REFRESH MATERIALIZED VIEW mv_base_apontamentos;
  END IF;
END;
$$;

-- ---------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------
REVOKE ALL ON FUNCTION printag_refresh_base() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION printag_get_classificacoes()                            TO authenticated;
GRANT EXECUTE ON FUNCTION printag_insert_classificacao(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_update_classificacao(INT, TEXT, TEXT, TEXT)     TO authenticated;
GRANT EXECUTE ON FUNCTION printag_delete_classificacao(INT)                       TO authenticated;
GRANT EXECUTE ON FUNCTION printag_refresh_base()                                  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS printag_delete_classificacao(INT);
-- DROP FUNCTION IF EXISTS printag_update_classificacao(INT, TEXT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS printag_insert_classificacao(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS printag_get_classificacoes();
-- DROP FUNCTION IF EXISTS printag_valida_dominio_classificacao(TEXT, TEXT, TEXT);
-- -- reexecutar o bloco 5 de 009_upload_rpcs.sql para voltar printag_refresh_base
-- NOTIFY pgrst, 'reload schema';

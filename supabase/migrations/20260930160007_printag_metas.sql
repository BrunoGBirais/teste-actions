-- =============================================
-- PrintAG — 007: Gestão de Metas de Equipamentos
-- =============================================

-- =======  UP  ========

-- 1) Função para listar as metas atuais (velocidade limite) de todos os equipamentos
DROP FUNCTION IF EXISTS printag_get_metas();
CREATE OR REPLACE FUNCTION printag_get_metas()
RETURNS TABLE (
  equipamento TEXT,
  area TEXT,
  velocidade_limite NUMERIC
) AS $$
BEGIN
  -- Apenas membros podem listar
  IF NOT printag_is_member() THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  RETURN QUERY
  SELECT 
    e.equipamento,
    e.area,
    e.velocidade_limite
  FROM aux_equipamento e
  ORDER BY e.area, e.equipamento;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2) Função para atualizar a velocidade limite de um equipamento
DROP FUNCTION IF EXISTS printag_update_meta(TEXT, NUMERIC);
CREATE OR REPLACE FUNCTION printag_update_meta(
  p_equipamento TEXT,
  p_velocidade NUMERIC
)
RETURNS VOID AS $$
BEGIN
  -- Apenas administradores podem alterar metas
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado. Apenas administradores podem editar as metas.';
  END IF;

  -- Se a meta for nula ou menor que 0, não faz nada ou salva como 0
  IF p_velocidade IS NULL OR p_velocidade < 0 THEN
    p_velocidade := 0;
  END IF;

  UPDATE aux_equipamento
  SET velocidade_limite = p_velocidade
  WHERE equipamento = p_equipamento;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Equipamento "%" não encontrado na base de dados.', p_equipamento;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Concede permissões para as novas funções
GRANT EXECUTE ON FUNCTION printag_get_metas() TO authenticated;
GRANT EXECUTE ON FUNCTION printag_update_meta(TEXT, NUMERIC) TO authenticated;

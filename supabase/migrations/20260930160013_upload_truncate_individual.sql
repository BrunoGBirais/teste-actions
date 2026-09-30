-- =========================================================
-- PrintAG — 013: Truncates individuais por tabela de upload
-- Resolve: snapshot_begin_v2 apagava todas as tabelas ao
-- fazer upload de apenas um dataset.
-- =========================================================

-- Truncate seletivo: apenas apontamentos
CREATE OR REPLACE FUNCTION printag_truncate_apontamentos()
  RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  TRUNCATE TABLE printag_apontamentos RESTART IDENTITY CASCADE;
END;
$$;

-- Truncate seletivo: apenas acabamentos
CREATE OR REPLACE FUNCTION printag_truncate_acabamentos()
  RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  TRUNCATE TABLE printag_acabamentos RESTART IDENTITY CASCADE;
END;
$$;

-- Truncate seletivo: apenas facas
CREATE OR REPLACE FUNCTION printag_truncate_facas()
  RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  TRUNCATE TABLE printag_facas RESTART IDENTITY CASCADE;
END;
$$;

-- As funções usam SECURITY DEFINER, então rodam com permissão do owner.
-- Nenhum GRANT adicional necessário.

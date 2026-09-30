-- =============================================
-- PrintAG — 002: Funções administrativas (tenant 'printag')
-- CRUD de usuários restrito a admins com
-- raw_user_meta_data->>'company_name' = 'printag'.
-- =============================================

-- =======  UP  ========

-- ---------- Helper: printag_is_admin ----------
CREATE OR REPLACE FUNCTION printag_is_admin()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_role TEXT;
  v_company TEXT;
BEGIN
  SELECT raw_user_meta_data->>'role',
         raw_user_meta_data->>'company_name'
    INTO v_role, v_company
    FROM auth.users
   WHERE id = auth.uid();
  RETURN v_company = 'printag' AND v_role = 'admin';
END;
$$;

-- ---------- printag_admin_list_users ----------
CREATE OR REPLACE FUNCTION printag_admin_list_users()
RETURNS TABLE(
  user_id    UUID,
  email      TEXT,
  full_name  TEXT,
  role       TEXT,
  created_at TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Only admins can list users';
  END IF;
  RETURN QUERY
    SELECT
      u.id AS user_id,
      u.email::TEXT,
      COALESCE(u.raw_user_meta_data->>'full_name', '')::TEXT,
      COALESCE(u.raw_user_meta_data->>'role', 'visualizador')::TEXT,
      u.created_at
    FROM auth.users u
    WHERE u.raw_user_meta_data->>'company_name' = 'printag'
    ORDER BY u.created_at DESC;
END;
$$;

-- ---------- printag_admin_confirm_user ----------
CREATE OR REPLACE FUNCTION printag_admin_confirm_user(p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Only admins can confirm users';
  END IF;
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
      raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                           || jsonb_build_object('company_name', 'printag'),
      updated_at = NOW()
  WHERE id = p_user_id
    AND (
      raw_user_meta_data->>'company_name' = 'printag'
      OR raw_user_meta_data->>'company_name' IS NULL
    );
END;
$$;

-- ---------- printag_admin_update_user ----------
-- Guarda: admin não pode mudar a própria role.
CREATE OR REPLACE FUNCTION printag_admin_update_user(
  p_user_id   UUID,
  p_full_name TEXT,
  p_role      TEXT DEFAULT NULL
)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
DECLARE
  new_meta JSONB;
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Only admins can update users';
  END IF;
  IF p_user_id = auth.uid() AND p_role IS NOT NULL THEN
    RAISE EXCEPTION 'Admins cannot change their own role';
  END IF;
  new_meta := jsonb_build_object('full_name', p_full_name);
  IF p_role IS NOT NULL THEN
    new_meta := new_meta || jsonb_build_object('role', p_role);
  END IF;
  UPDATE auth.users
  SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || new_meta,
      updated_at = NOW()
  WHERE id = p_user_id
    AND raw_user_meta_data->>'company_name' = 'printag';
END;
$$;

-- ---------- printag_admin_delete_user ----------
-- Guarda: admin não pode se auto-deletar.
CREATE OR REPLACE FUNCTION printag_admin_delete_user(p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT printag_is_admin() THEN
    RAISE EXCEPTION 'Only admins can delete users';
  END IF;
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Admins cannot delete themselves';
  END IF;
  DELETE FROM auth.users
  WHERE id = p_user_id
    AND raw_user_meta_data->>'company_name' = 'printag';
END;
$$;

-- ---------- GRANTs ----------
GRANT EXECUTE ON FUNCTION printag_is_admin()                          TO authenticated;
GRANT EXECUTE ON FUNCTION printag_admin_list_users()                  TO authenticated;
GRANT EXECUTE ON FUNCTION printag_admin_confirm_user(UUID)            TO authenticated;
GRANT EXECUTE ON FUNCTION printag_admin_update_user(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION printag_admin_delete_user(UUID)             TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- REVOKE EXECUTE ON FUNCTION printag_admin_delete_user(UUID)             FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_admin_update_user(UUID, TEXT, TEXT) FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_admin_confirm_user(UUID)            FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_admin_list_users()                  FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION printag_is_admin()                          FROM authenticated;
-- DROP FUNCTION IF EXISTS printag_admin_delete_user(UUID);
-- DROP FUNCTION IF EXISTS printag_admin_update_user(UUID, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS printag_admin_confirm_user(UUID);
-- DROP FUNCTION IF EXISTS printag_admin_list_users();
-- DROP FUNCTION IF EXISTS printag_is_admin();
-- NOTIFY pgrst, 'reload schema';

-- =============================================================
-- PrintAG — 032: RLS lockdown do schema public
--
-- Contexto: a SUPABASE_ANON_KEY vai no bundle do front, ou seja, é
-- pública. Sem RLS, qualquer pessoa lia todas as tabelas via
-- /rest/v1/<tabela>. O front NUNCA acessa tabela direto — só chama
-- RPCs printag_* (todas SECURITY DEFINER, GRANT EXECUTE apenas para
-- `authenticated`), então travar as tabelas não quebra a aplicação.
--
-- Quem continua enxergando os dados:
--   * dono das tabelas / service_role  → BYPASSRLS (n8n usa essas)
--   * funções SECURITY DEFINER          → rodam como o dono
--   * printag_agent_ro                  → policy de SELECT criada abaixo
--
-- ATENÇÃO: tabelas criadas por migrations FUTURAS não são cobertas
-- por este arquivo (ele roda uma vez só). Toda migration nova que
-- criar tabela precisa repetir ENABLE ROW LEVEL SECURITY + a policy
-- do printag_agent_ro.
-- =============================================================

-- =======  UP  ========

DO $$
DECLARE
  r           record;
  tem_agente  boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'printag_agent_ro')
    INTO tem_agente;

  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.relname);

    -- Sem policy nenhuma, RLS já bloqueia anon e authenticated.
    -- O agente do n8n é NOBYPASSRLS (migration 004), então precisa
    -- de uma policy explícita de leitura.
    IF tem_agente THEN
      EXECUTE format(
        'DROP POLICY IF EXISTS %I ON %I.%I',
        'printag_agent_ro_select', 'public', r.relname);
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I '
        || 'FOR SELECT TO printag_agent_ro USING (true)',
        'printag_agent_ro_select', 'public', r.relname);
    END IF;
  END LOOP;
END$$;

-- Defesa em profundidade: tira o privilégio de tabela também.
-- Cobre tabelas e views comuns (views ignoram a RLS da tabela base,
-- porque rodam com os direitos de quem as criou).
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

-- Materialized views não entram em "ALL TABLES" e não suportam RLS:
-- só o REVOKE protege.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'm'
  LOOP
    EXECUTE format(
      'REVOKE ALL ON public.%I FROM anon, authenticated', r.relname);
  END LOOP;
END$$;

-- PostgREST precisa reler privilegios/schema depois do revoke
NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DO $$
-- DECLARE r record;
-- BEGIN
--   FOR r IN SELECT c.relname FROM pg_class c
--            JOIN pg_namespace n ON n.oid = c.relnamespace
--            WHERE n.nspname = 'public' AND c.relkind = 'r'
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 'printag_agent_ro_select', 'public', r.relname);
--     EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY', r.relname);
--   END LOOP;
-- END$$;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated;

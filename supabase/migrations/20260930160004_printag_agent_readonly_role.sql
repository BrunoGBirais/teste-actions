-- =============================================================
-- PrintAG — 004: Role read-only para o agente IA (consulta_sql)
-- Role dedicado com SELECT apenas em tabelas/views públicas.
-- Sem escrita, sem CREATE, sem EXECUTE em funções.
-- Esta é a credencial Postgres usada NO SUB-WORKFLOW do agente.
-- =============================================================

-- =======  UP  ========

-- Criado sem senha (ninguém consegue logar). Defina a senha por ambiente,
-- fora do git, no SQL Editor:
--   ALTER ROLE printag_agent_ro PASSWORD '<senha forte>';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'printag_agent_ro') THEN
    CREATE ROLE printag_agent_ro LOGIN PASSWORD NULL
      NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
      CONNECTION LIMIT 5;
  END IF;
END$$;

-- Zera privilégios herdados
REVOKE ALL ON DATABASE postgres FROM printag_agent_ro;
REVOKE ALL ON SCHEMA public  FROM printag_agent_ro;
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM printag_agent_ro;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM printag_agent_ro;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM printag_agent_ro;

-- Acesso mínimo necessário
GRANT CONNECT ON DATABASE postgres TO printag_agent_ro;
GRANT USAGE   ON SCHEMA   public   TO printag_agent_ro;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO printag_agent_ro;

-- Objetos FUTUROS criados no schema public também ganham SELECT
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO printag_agent_ro;

-- Defesa em profundidade: nega escrita explicitamente
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public FROM printag_agent_ro;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLES FROM printag_agent_ro;

-- Sem CREATE no schema
REVOKE CREATE ON SCHEMA public FROM printag_agent_ro;

-- NÃO conceder EXECUTE em funções (evita RPCs que façam escrita).
-- Para liberar uma função pontual de leitura, faça:
--   GRANT EXECUTE ON FUNCTION public.nome_funcao(args) TO printag_agent_ro;

-- Timeouts: derruba queries longas para proteger o banco
ALTER ROLE printag_agent_ro SET statement_timeout                  = '15s';
ALTER ROLE printag_agent_ro SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE printag_agent_ro SET lock_timeout                       = '5s';

-- Obedece RLS normal
ALTER ROLE printag_agent_ro NOBYPASSRLS;

-- =======  DOWN  ========
-- REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM printag_agent_ro;
-- REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM printag_agent_ro;
-- REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM printag_agent_ro;
-- REVOKE ALL ON SCHEMA public  FROM printag_agent_ro;
-- REVOKE ALL ON DATABASE postgres FROM printag_agent_ro;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM printag_agent_ro;
-- DROP ROLE IF EXISTS printag_agent_ro;

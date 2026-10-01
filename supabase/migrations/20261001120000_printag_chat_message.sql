-- Tabela de memória do chat (printag_chat_message).
-- O nó Postgres Chat Memory do n8n cria a tabela sozinho no primeiro uso, só
-- com id, session_id e message. Os workflows printag-Chat-GET-Sessions usam
-- created_at, e a tabela nascia fora do rls_lockdown (aberta para anon).

CREATE TABLE IF NOT EXISTS public.printag_chat_message (
  id         serial PRIMARY KEY,
  session_id varchar(255) NOT NULL,
  message    jsonb NOT NULL
);

ALTER TABLE public.printag_chat_message
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS printag_chat_message_session_id_idx
  ON public.printag_chat_message (session_id);

-- Só o n8n (role postgres) acessa; nada via PostgREST.
ALTER TABLE public.printag_chat_message ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.printag_chat_message FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';

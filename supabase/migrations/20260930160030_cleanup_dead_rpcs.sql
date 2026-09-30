-- =============================================
-- PrintAG — 030: Remove RPCs mortas (sem nenhum caller)
--
-- Auditoria (2026-08-27) em front-react/src, front-react/dist (bundle
-- deployado) e todos os workflows/n8n/*.json (incluindo _archive): nenhuma
-- chamada encontrada para:
--   - printag_dashboard_kpis/status_os/producao_diaria/paradas_maquina/
--     refugo_por_setor/equipamentos (003_printag_dashboard_functions.sql)
--     — substituídas em produção por printag_ind_*/printag_indm_*/printag_oee_*.
--   - printag_get_metas() / printag_update_meta() (007_printag_metas.sql)
--     — substituídas por printag_get_metas_maquinas/printag_update_metas_maquina;
--     só eram chamadas por front/front.html, removido do repositório.
--
-- Views vw_status_os/vw_producao_diaria/vw_tempo_parada_maquina/
-- vw_refugo_por_setor e as tabelas Gen 1 (ordens_servico/apontamentos/facas)
-- NÃO são tocadas aqui: seguem em uso pela tool consulta_sql do agente de
-- IA e pela aba "OEE Geral" do front-react (printag_oee_*).
-- =============================================

-- =======  UP  ========

DROP FUNCTION IF EXISTS printag_dashboard_kpis(INT);
DROP FUNCTION IF EXISTS printag_dashboard_status_os(INT);
DROP FUNCTION IF EXISTS printag_dashboard_producao_diaria(INT);
DROP FUNCTION IF EXISTS printag_dashboard_paradas_maquina(INT);
DROP FUNCTION IF EXISTS printag_dashboard_refugo_por_setor(INT);
DROP FUNCTION IF EXISTS printag_dashboard_equipamentos(INT);
DROP FUNCTION IF EXISTS printag_get_metas();
DROP FUNCTION IF EXISTS printag_update_meta(TEXT, NUMERIC);

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Recriar a partir de 003_printag_dashboard_functions.sql e 007_printag_metas.sql.
-- NOTIFY pgrst, 'reload schema';

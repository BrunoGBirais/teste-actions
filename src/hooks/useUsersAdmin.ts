import { useCallback, useState } from "react";
import { sbAuth } from "../services/supabase";
import { sbRpc } from "../services/supabase";
import { COMPANY_NAME } from "../config/constants";
import type { AdminUser } from "../types/admin";

export function useUsersAdmin() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState<{ text: string; type?: "error" }>({ text: "" });

  const load = useCallback(async () => {
    setLoading(true);
    setStatus({ text: "" });
    try {
      const rows = await sbRpc<AdminUser[]>("printag_admin_list_users", {});
      setUsers(Array.isArray(rows) ? rows : []);
    } catch (err) {
      setUsers([]);
      setStatus({ text: (err as Error).message || "Erro ao carregar usuários", type: "error" });
    } finally {
      setLoading(false);
    }
  }, []);

  const createUser = useCallback(
    async (fullName: string, email: string, password: string, role: string) => {
      const signup = await sbAuth<{ user?: { id?: string }; id?: string }>("signup", {
        email,
        password,
        data: { full_name: fullName, role, company_name: COMPANY_NAME },
      });
      const newId = signup?.user?.id || signup?.id;
      if (newId) {
        try {
          await sbRpc("printag_admin_confirm_user", { p_user_id: newId });
        } catch (confirmErr) {
          console.warn("Falha ao confirmar usuário:", confirmErr);
          throw new Error(
            "Usuário criado no Supabase, mas a confirmação falhou. Se você estiver usando o login 'admin' falso, use um admin real.",
          );
        }
      }
      setStatus({ text: "Usuário criado e confirmado." });
      await load();
    },
    [load],
  );

  const updateUser = useCallback(
    async (id: string, fullName: string, role: string) => {
      await sbRpc("printag_admin_update_user", { p_user_id: id, p_full_name: fullName, p_role: role });
      setStatus({ text: "Usuário atualizado." });
      await load();
    },
    [load],
  );

  const deleteUser = useCallback(
    async (id: string) => {
      setStatus({ text: "Excluindo..." });
      try {
        await sbRpc("printag_admin_delete_user", { p_user_id: id });
        setStatus({ text: "Usuário excluído." });
      } catch (err) {
        setStatus({ text: (err as Error).message || "Erro ao excluir usuário", type: "error" });
      }
      await load();
    },
    [load],
  );

  return { users, loading, status, load, createUser, updateUser, deleteUser };
}

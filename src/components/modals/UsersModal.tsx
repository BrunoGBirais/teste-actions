import { useEffect, useState } from "react";
import { Pencil, Trash2, UserPlus, UsersRound, X } from "lucide-react";
import { useAuth } from "../../context/AuthContext";
import { useUsersAdmin } from "../../hooks/useUsersAdmin";
import type { AdminUser } from "../../types/admin";

interface UsersModalProps {
  open: boolean;
  onClose: () => void;
}

type FormMode = "create" | "edit";

export function UsersModal({ open, onClose }: UsersModalProps) {
  const { currentUser } = useAuth();
  const admin = useUsersAdmin();
  const myId = currentUser?.sub || currentUser?.id;

  const [formOpen, setFormOpen] = useState(false);
  const [formMode, setFormMode] = useState<FormMode>("create");
  const [formError, setFormError] = useState("");
  const [saving, setSaving] = useState(false);
  const [editId, setEditId] = useState("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState("visualizador");

  useEffect(() => {
    if (open) admin.load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  function openForm(mode: FormMode, user?: AdminUser) {
    setFormMode(mode);
    setFormError("");
    setEditId(user?.id || user?.user_id || "");
    setName(user?.full_name || "");
    setEmail(user?.email || "");
    setPassword("");
    setRole(((user?.role || user?.user_role || "visualizador") as string).toLowerCase() === "admin" ? "admin" : "visualizador");
    setFormOpen(true);
  }

  async function handleFormSubmit() {
    setSaving(true);
    setFormError("");
    try {
      if (formMode === "edit") {
        await admin.updateUser(editId, name.trim(), role);
      } else {
        if (!email.trim() || password.length < 6) {
          throw new Error("Informe e-mail e senha (mínimo 6 caracteres).");
        }
        await admin.createUser(name.trim(), email.trim(), password, role);
      }
      setFormOpen(false);
    } catch (err) {
      setFormError((err as Error).message || "Erro ao salvar usuário");
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(user: AdminUser) {
    const id = user.id || user.user_id || "";
    const name = user.full_name || user.email || "este usuário";
    if (!confirm(`Excluir ${name} permanentemente? Esta ação não pode ser desfeita.`)) return;
    await admin.deleteUser(id);
  }

  return (
    <>
      <div className={`confirm-modal-backdrop${open ? " active" : ""}`} onClick={(e) => e.target === e.currentTarget && onClose()}>
        <div className="confirm-modal admin-modal">
          <div className="admin-modal-header">
            <h3 className="confirm-title" style={{ margin: 0 }}>
              <UsersRound style={{ width: 18, height: 18, verticalAlign: -3, marginRight: 6 }} />
              Gerenciar usuários
            </h3>
            <button className="admin-close-btn" title="Fechar" onClick={onClose}>
              <X style={{ width: 18, height: 18 }} />
            </button>
          </div>
          <div className="admin-modal-toolbar">
            <button className="btn-modal btn-confirm" onClick={() => openForm("create")}>
              <UserPlus style={{ width: 14, height: 14, verticalAlign: -2, marginRight: 4 }} />
              Novo usuário
            </button>
            <div className={`admin-modal-status${admin.status.type === "error" ? " error" : ""}`}>{admin.status.text}</div>
          </div>
          <div className="admin-users-list">
            {admin.loading ? (
              <div className="admin-empty">Carregando...</div>
            ) : admin.users.length === 0 ? (
              <div className="admin-empty">Nenhum usuário encontrado.</div>
            ) : (
              admin.users.map((u) => {
                const id = u.id || u.user_id || "";
                const role = u.role || u.user_role || "visualizador";
                const isSelf = id === myId;
                return (
                  <div className="admin-user-row" key={id}>
                    <div className="admin-user-info">
                      <div className="admin-user-name">
                        {u.full_name || "(sem nome)"}
                        {isSelf && (
                          <span style={{ fontSize: 11, color: "var(--text-secondary)", fontWeight: 400 }}> (você)</span>
                        )}
                      </div>
                      <div className="admin-user-email">{u.email || ""}</div>
                    </div>
                    <span className={`admin-role-badge ${role === "admin" ? "admin-role-admin" : "admin-role-visualizador"}`}>
                      {role === "admin" ? "Admin" : "Visualizador"}
                    </span>
                    <div className="admin-row-actions">
                      <button className="admin-icon-btn" title="Editar" onClick={() => openForm("edit", u)}>
                        <Pencil style={{ width: 14, height: 14 }} />
                      </button>
                      <button className="admin-icon-btn danger" title="Excluir" disabled={isSelf} onClick={() => handleDelete(u)}>
                        <Trash2 style={{ width: 14, height: 14 }} />
                      </button>
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>

      <div className={`confirm-modal-backdrop${formOpen ? " active" : ""}`} onClick={(e) => e.target === e.currentTarget && setFormOpen(false)}>
        <div className="confirm-modal admin-form-modal">
          <div className="admin-modal-header">
            <h3 className="confirm-title" style={{ margin: 0 }}>
              {formMode === "edit" ? "Editar usuário" : "Novo usuário"}
            </h3>
            <button className="admin-close-btn" title="Fechar" type="button" onClick={() => setFormOpen(false)}>
              <X style={{ width: 18, height: 18 }} />
            </button>
          </div>
          <form
            className="admin-form"
            onSubmit={(e) => {
              e.preventDefault();
              handleFormSubmit();
            }}
          >
            <label className="admin-form-label">
              Nome completo
              <input
                type="text"
                className="login-input"
                placeholder="Ex.: Maria da Silva"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </label>
            {formMode === "create" && (
              <label className="admin-form-label">
                E-mail
                <input
                  type="email"
                  className="login-input"
                  placeholder="usuario@empresa.com.br"
                  autoComplete="off"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                />
              </label>
            )}
            {formMode === "create" && (
              <label className="admin-form-label">
                Senha provisória
                <input
                  type="password"
                  className="login-input"
                  placeholder="Mínimo 6 caracteres"
                  autoComplete="new-password"
                  minLength={6}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                />
              </label>
            )}
            <label className="admin-form-label">
              Cargo
              <select className="login-input" required value={role} onChange={(e) => setRole(e.target.value)}>
                <option value="visualizador">Visualizador</option>
                <option value="admin">Administrador</option>
              </select>
            </label>
            {formError && <div className="err-msg" style={{ display: "block" }}>{formError}</div>}
            <div className="confirm-actions">
              <button type="button" className="btn-modal btn-cancel" onClick={() => setFormOpen(false)}>
                Cancelar
              </button>
              <button type="submit" className="btn-modal btn-confirm" disabled={saving}>
                Salvar
              </button>
            </div>
          </form>
        </div>
      </div>
    </>
  );
}

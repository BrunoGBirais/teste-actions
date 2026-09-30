import { useState, type FormEvent } from "react";
import { useAuth } from "../context/AuthContext";
import logoPrintImage from "../assets/login/logo-print.png";

// Next.js static image imports are objects; the plain <img> tags need the URL.
const logoPrint = logoPrintImage.src;

export function LoginPage() {
  const { login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [emailReadOnly, setEmailReadOnly] = useState(true);
  const [passwordReadOnly, setPasswordReadOnly] = useState(true);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError("");
    const result = await login(email.trim(), password);
    setSubmitting(false);
    if (!result.ok) {
      setError(result.error || "Credenciais inválidas");
    }
  }

  return (
    <div className="login-overlay" id="loginOverlay">
      <div className="nv-screen">
        {/* Left: brand / hero panel */}
        <aside className="nv-hero">
          <div className="nv-hero-top">
            <div className="nv-brand">
              <img className="nv-brand-logo" src={logoPrint} alt="PRINT iAG" />
            </div>
            <div className="nv-hero-tag">Portal do Agente</div>
          </div>

          <div className="nv-hero-mid">
            <p className="nv-hero-eyebrow">Desde 1973</p>
            <p className="nv-hero-title-intro">Bem-vindo de volta ao seu</p>
            <h1 className="nv-hero-title">Agente de I.A.</h1>
            <p className="nv-hero-sub">
              Acesse suas ferramentas de automação inteligente, painéis de análise e insights — tudo em um só
              lugar.
            </p>

            <div className="nv-hero-features">
              <div className="nv-hero-feature">
                <div className="nv-hero-feature-icon">
                  <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round">
                    <path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" />
                  </svg>
                </div>
                <div>
                  <p className="nv-hero-feature-title">Vantagem Competitiva</p>
                  <p className="nv-hero-feature-desc">Processos mais rápidos com fluxos inteligentes.</p>
                </div>
              </div>
              <div className="nv-hero-feature">
                <div className="nv-hero-feature-icon">
                  <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1" />
                    <circle cx="12" cy="12" r="3.2" />
                  </svg>
                </div>
                <div>
                  <p className="nv-hero-feature-title">Inteligência Artificial</p>
                  <p className="nv-hero-feature-desc">Impulsionando a produtividade.</p>
                </div>
              </div>
              <div className="nv-hero-feature">
                <div className="nv-hero-feature-icon">
                  <svg viewBox="0 0 24 24" fill="none" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round">
                    <path d="M4 20V10M11 20V4M18 20v-7" />
                  </svg>
                </div>
                <div>
                  <p className="nv-hero-feature-title">Análises em Tempo Real</p>
                  <p className="nv-hero-feature-desc">Acompanhe o desempenho com dashboards inteligentes.</p>
                </div>
              </div>
            </div>
          </div>

          <div className="nv-hero-bottom">© 2026 PrinT iAG — Todos os direitos reservados</div>
        </aside>

        {/* Mobile-only brand header */}
        <header className="nv-mobile-brand">
          <img src={logoPrint} alt="PRINT iAG" />
        </header>

        {/* Right: login form panel */}
        <main className="nv-panel">
          <div className="nv-form-wrap">
            <p className="nv-form-label-mono">Acesso ao painel</p>
            <h2 className="nv-form-title">Entrar na sua conta</h2>

            <form id="loginForm" noValidate onSubmit={handleSubmit}>
              {/* Dummy inputs to absorb aggressive browser autofill */}
              <input type="text" style={{ position: "absolute", top: -9999, left: -9999 }} tabIndex={-1} autoComplete="username" />
              <input type="password" style={{ position: "absolute", top: -9999, left: -9999 }} tabIndex={-1} autoComplete="current-password" />

              <div className="nv-field">
                <label htmlFor="usernameInput">E-mail</label>
                <div className="nv-input-wrap">
                  <input
                    type="text"
                    className="nv-input"
                    id="usernameInput"
                    placeholder="voce@empresa.com.br"
                    autoComplete="off"
                    readOnly={emailReadOnly}
                    onFocus={() => setEmailReadOnly(false)}
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                  />
                </div>
              </div>

              <div className="nv-field">
                <label htmlFor="passwordInput">Senha</label>
                <div className="nv-input-wrap">
                  <input
                    type={showPassword ? "text" : "password"}
                    className="nv-input"
                    id="passwordInput"
                    placeholder="Sua senha"
                    autoComplete="new-password"
                    readOnly={passwordReadOnly}
                    onFocus={() => setPasswordReadOnly(false)}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                  />
                  <button
                    type="button"
                    className="nv-toggle-visibility"
                    aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
                    onClick={() => setShowPassword((v) => !v)}
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round">
                      <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7Z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                  </button>
                </div>
              </div>

              <div className="nv-row-between" />

              <button type="submit" className="nv-btn-primary" disabled={submitting}>
                {submitting ? "Entrando..." : "Entrar"}
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
                  <path d="M5 12h14M13 6l6 6-6 6" />
                </svg>
              </button>
              <div className="nv-form-error" style={{ display: error ? "block" : "none" }}>
                {error}
              </div>
            </form>

            <div className="nv-form-copyright">
              <span className="nv-form-copyright-label">Gerando inovação através de inteligência artificial</span>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

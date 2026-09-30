import type { Metadata } from "next";
import type { ReactNode } from "react";
import "highlight.js/styles/github-dark.min.css";
import "../styles/legacy.css";
import { AppShell } from "../layout/AppShell";

export const metadata: Metadata = {
  title: "PRINT iAG",
  description: "Portal do Agente de I.A. da PRINT iAG",
};

// Applies the saved theme before first paint, so dark-mode users don't see a
// light flash while React hydrates (ThemeContext keeps it in sync afterwards).
const themeScript = `try{var t=localStorage.getItem("theme");if(t)document.documentElement.setAttribute("data-theme",t)}catch(e){}`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="pt-BR" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>
        <AppShell>{children}</AppShell>
      </body>
    </html>
  );
}

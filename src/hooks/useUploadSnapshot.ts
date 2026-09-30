import { useCallback, useState } from "react";
import { sbRpc } from "../services/supabase";
import { brDateISO, brDec, brInt, col, parseBrDateTime, parseCsv } from "../lib/csv";
import { limparArquivo, resumirLaudo } from "../lib/encoding";

export type DatasetKey = "apontamentos" | "acabamento" | "facas";

export interface LogLine {
  text: string;
  kind?: "ok" | "err";
}

// Um dataset lido, limpo, mapeado e validado — pronto para ir ao banco.
interface Preparado {
  rotulo: string;
  rows: Record<string, string | null>[];
  truncateRpc: string;
  snapshotRpc: string;
  /** [pct inicial, pct final] da barra de progresso durante o envio. */
  faixa: [number, number];
}

const CHUNK = 300;

export function useUploadSnapshot() {
  const [files, setFiles] = useState<Record<DatasetKey, File | null>>({ apontamentos: null, acabamento: null, facas: null });
  const [log, setLog] = useState<LogLine[]>([]);
  const [progress, setProgress] = useState({ pct: 0, label: "" });
  const [running, setRunning] = useState(false);

  const setFile = useCallback((key: DatasetKey, file: File | null) => {
    setFiles((prev) => ({ ...prev, [key]: file }));
  }, []);

  const addLog = useCallback((text: string, kind?: "ok" | "err") => {
    setLog((prev) => [...prev, { text, kind }]);
  }, []);

  const hasAnyFile = !!(files.apontamentos || files.acabamento || files.facas);

  // Quando o mapeamento zera, o problema quase sempre e o nome/separador das
  // colunas: mostrar o cabecalho lido evita adivinhacao.
  const logHeaderMismatch = useCallback(
    (dataset: string, headers: string[], obrigatorias: string[]) => {
      addLog(`❌ Nenhuma linha válida encontrada no CSV de ${dataset}. Nada foi alterado no banco.`, "err");
      addLog(`   Colunas obrigatórias: ${obrigatorias.join(" | ")}`, "err");
      addLog(`   Colunas lidas no arquivo (${headers.length}): ${headers.join(" | ")}`, "err");
      addLog("   Confira se o arquivo foi exportado com as mesmas colunas do relatório original.", "err");
    },
    [addLog],
  );

  // Le o arquivo passando pela limpeza de encoding antes do parser: o CSV chega
  // ao mapeamento em ASCII puro, sem acento e sem caractere corrompido.
  // Devolve null quando a limpeza para em pendencia — arquivo com palavra
  // ilegivel que o glossario nao resolve; seguir gravaria um chute no banco.
  const lerPlanilha = useCallback(
    async (rotulo: string, file: File) => {
      addLog(`⏳ Lendo ${rotulo}…`);
      const { texto, laudo } = await limparArquivo(file);
      for (const linha of resumirLaudo(laudo)) addLog(linha.texto, linha.kind);
      if (texto === null) {
        addLog(`❌ ${rotulo}: arquivo reprovado na limpeza de encoding. Nada foi alterado no banco.`, "err");
        addLog("   Reexporte a planilha em UTF-8 ou registre os termos acima no glossário (src/lib/glossarioEncoding.ts).", "err");
        return null;
      }
      const parsed = parseCsv(texto);
      addLog(`   ${parsed.rows.length.toLocaleString("pt-BR")} linhas encontradas.`);
      return parsed;
    },
    [addLog],
  );

  const run = useCallback(async () => {
    setRunning(true);
    setLog([]);
    setProgress({ pct: 0, label: "0%" });
    const falhar = () => setProgress({ pct: 0, label: "Erro de dados" });
    try {
      addLog("⏳ Iniciando snapshot…");

      // Fase 1: ler, limpar, mapear e validar TUDO antes de tocar no banco.
      // Um arquivo invalido no meio do lote nao pode deixar a base pela metade.
      const preparados: Preparado[] = [];

      if (files.apontamentos) {
        setProgress({ pct: 2, label: "Lendo Apontamentos…" });
        const parsed = await lerPlanilha("Apontamentos", files.apontamentos);
        if (!parsed) return falhar();
        const mapped = parsed.rows
          .map((r) => ({
            equipamento: col(r, "codeq.Nome do equipamento", "Nome do equipamento"),
            inicio: col(r, "Início", "Inicio"),
            fim: col(r, "Fim"),
            tipo_apontam: col(r, "Tipo apontam.", "Tipo apontam"),
            motivo: col(r, "codmp.Descrição", "codmp.Descricao"),
            nro_os: String(col(r, "numos.Nro OS", "Nro OS")),
            produzido: String(brInt(col(r, "Produzido")) ?? 0),
            titulo_produto: col(r, "numos.Título", "numos.Titulo"),
            nome_cliente: col(r, "numos.Nome cliente", "Nome cliente"),
            operador: col(r, "Operador"),
          }))
          .filter((r) => r.equipamento && r.inicio);

        const invalidos = mapped.filter((r) => {
          const ini = parseBrDateTime(r.inicio);
          const fim = parseBrDateTime(r.fim);
          return ini && fim && fim < ini;
        });
        if (invalidos.length > 0) {
          addLog(`❌ ${invalidos.length} apontamento(s) com "Fim" anterior ao "Início":`, "err");
          invalidos.forEach((r) => addLog(`   • ${r.equipamento} | Início: ${r.inicio}  →  Fim: ${r.fim}`, "err"));
          addLog("Corrija esses registros na planilha de origem e importe novamente.", "err");
          return falhar();
        }

        if (mapped.length === 0) {
          logHeaderMismatch("Apontamentos", parsed.headers, [
            "codeq.Nome do equipamento",
            "Início",
            "Tipo apontam.",
          ]);
          return falhar();
        }

        preparados.push({
          rotulo: "Apontamentos",
          rows: mapped,
          truncateRpc: "printag_truncate_apontamentos",
          snapshotRpc: "printag_snapshot_apontamentos_v2",
          faixa: [15, 60],
        });
      }

      if (files.acabamento) {
        setProgress({ pct: 6, label: "Lendo Tipo Acabamento…" });
        const parsed = await lerPlanilha("Tipo Acabamento", files.acabamento);
        if (!parsed) return falhar();
        const mapped = parsed.rows
          .map((r) => ({
            nro_os: String(col(r, "Nro OS")),
            equipamento_plan: col(r, "pcpeq.Nome do equipamento", "Nome do equipamento", "Máquina"),
            nome_cliente: col(r, "numos.Nome cliente", "Nome cliente", "Cliente"),
            descricao_servico: col(r, "Descrição do Serviço", "Descricao do Servico"),
            tipo_acabamento: col(r, "Descrição", "Descricao"),
            hrs_pcp: String(brDec(col(r, "NºHrs PCP", "NHrs PCP", "Hrs PCP")) ?? ""),
            quantidade: String(brInt(col(r, "Quantidade")) ?? ""),
            ini_calculado: brDateISO(col(r, "Ini calculado", "Ini Calculado")),
            fim_calculado: brDateISO(col(r, "Fim calculado", "Fim Calculado")),
          }))
          .filter((r) => r.nro_os);
        if (mapped.length === 0) {
          logHeaderMismatch("Acabamento", parsed.headers, ["Nro OS"]);
          return falhar();
        }
        preparados.push({
          rotulo: "Acabamento",
          rows: mapped,
          truncateRpc: "printag_truncate_acabamentos",
          snapshotRpc: "printag_snapshot_acabamentos_v2",
          faixa: [65, 85],
        });
      }

      if (files.facas) {
        setProgress({ pct: 10, label: "Lendo Metros Lineares / Facas…" });
        const parsed = await lerPlanilha("Metros Lineares / Facas", files.facas);
        if (!parsed) return falhar();
        const mapped = parsed.rows
          .map((r) => ({
            nro_os: String(col(r, "Nro OS")),
            faca: col(r, "Faca"),
            lado_1: String(brDec(col(r, "faca.Lado 1")) ?? ""),
            lado_2: String(brDec(col(r, "faca.Lado 2")) ?? ""),
            montagem: String(brInt(col(r, "faca.Montagem", "Montagem")) ?? ""),
            medida_total: col(r, "faca.Medida total"),
            l1_total: String(brDec(col(r, "faca.L1 total")) ?? ""),
            l2_total: String(brDec(col(r, "faca.L2 total")) ?? ""),
            fto_final: String(brInt(col(r, "faca.Fto.final")) ?? ""),
            fto_impr: String(brInt(col(r, "faca.Fto.Impr.")) ?? ""),
            l1_substrato: String(brDec(col(r, "faca.L1 substrato")) ?? ""),
            l2_substrato: String(brDec(col(r, "faca.L2 substrato")) ?? ""),
            l1_corte: String(brDec(col(r, "faca.L1 corte")) ?? ""),
            l2_corte: String(brDec(col(r, "faca.L2 corte")) ?? ""),
          }))
          .filter((r) => r.nro_os);
        if (mapped.length === 0) {
          logHeaderMismatch("Facas", parsed.headers, ["Nro OS"]);
          return falhar();
        }
        preparados.push({
          rotulo: "Facas",
          rows: mapped,
          truncateRpc: "printag_truncate_facas",
          snapshotRpc: "printag_snapshot_facas_v2",
          faixa: [88, 98],
        });
      }

      // Fase 2: so agora escreve. Truncate seguido do envio em lotes.
      for (const p of preparados) {
        const [inicio, fim] = p.faixa;
        setProgress({ pct: inicio, label: `Limpando ${p.rotulo} anteriores…` });
        await sbRpc(p.truncateRpc, {});
        addLog(`✅ ${p.rotulo}: registros anteriores removidos.`, "ok");

        const total = p.rows.length;
        let sent = 0;
        for (let i = 0; i < total; i += CHUNK) {
          await sbRpc(p.snapshotRpc, { p_rows: p.rows.slice(i, i + CHUNK) });
          sent += Math.min(CHUNK, total - i);
          setProgress({
            pct: inicio + Math.round((sent / total) * (fim - inicio)),
            label: `${p.rotulo} ${sent.toLocaleString("pt-BR")} / ${total.toLocaleString("pt-BR")}`,
          });
        }
        addLog(`✅ ${p.rotulo}: ${total.toLocaleString("pt-BR")} registros enviados.`, "ok");
      }

      setProgress({ pct: 98, label: "Atualizando base analítica…" });
      addLog("⏳ Atualizando visão analítica (pode levar 30-60s)…");
      try {
        await sbRpc("printag_refresh_base", {});
        addLog("✅ Base analítica atualizada.", "ok");
      } catch (err) {
        addLog("❌ Falha ao atualizar a base analítica: " + ((err as Error).message || err), "err");
        addLog("Os dados foram enviados, mas o dashboard ficará vazio até o refresh rodar.", "err");
      }

      setProgress({ pct: 100, label: "Concluído!" });
      addLog("🎉 Snapshot enviado com sucesso!", "ok");
      addLog("⏳ Clique em Atualizar no painel do dashboard.", "ok");
    } catch (err) {
      addLog("❌ Erro: " + ((err as Error).message || err), "err");
      setProgress({ pct: 0, label: "Erro" });
    } finally {
      setRunning(false);
    }
  }, [files, addLog, lerPlanilha, logHeaderMismatch]);

  return { files, setFile, hasAnyFile, log, progress, running, run };
}

// Loose row shapes for Postgres RPC results: fields are optional/nullable
// because the RPCs can return partial rows depending on filters.
export interface OeeKpis {
  oee_operacional?: number | null;
  qtd_produzido?: number | null;
  disp_operacional?: number | null;
  min_virando?: number | null;
  desempenho?: number | null;
  vel_media_virando?: number | null;
  tempo_medio_acerto_h?: number | null;
  indice_improdutivos?: number | null;
  min_acerto?: number | null;
}

export interface OeePorSemanaRow {
  semana?: number | string;
  oee_operacional?: number | null;
  disp_operacional?: number | null;
  desempenho?: number | null;
  vel_media_virando?: number | null;
  meta_velocidade?: number | null;
  tempo_medio_acerto_h?: number | null;
  indice_improdutivos?: number | null;
}

export interface ParetoRow {
  classificacao_perda?: string;
  apontamento?: string;
  horas_parado?: number | null;
  pct_acumulado?: number | null;
  horas_improdutivas_area?: number | null;
  horas_improdutivas_gerencial?: number | null;
}

export interface ProducaoTipoRow {
  tipo_acabamento?: string | null;
  equipamento_plan?: string | null;
  qtd_produzida?: number | null;
}

export interface PorEquipamentoRow {
  equipamento?: string;
  vel_media_virando?: number | null;
  meta_velocidade?: number | null;
}

export interface AcertoTipoRow {
  tipo_acabamento?: string;
  tempo_medio_acerto_h?: number | null;
}

export interface FiltrosDisponiveis {
  equipamentos?: string[];
  operadores?: string[];
  tipos_acabamento?: string[];
  anos?: number[];
  semanas?: number[];
}

export interface MaquinaFiltro {
  id: number | string;
  nome: string;
  area: string;
}

export interface IndFiltros {
  maquinas?: MaquinaFiltro[];
  semanas?: number[];
  meses?: number[];
  operadores?: string[];
}

export interface IndSemanaRow {
  semana: number;
  ano?: number;
  mes?: number;
  quantidade_acerto?: number | null;
  acerto_hrs?: number | null;
  virando_hrs?: number | null;
  produzido_virando?: number | null;
  produzido_total?: number | null;
  horas_improdutivas_area?: number | null;
  horas_improdutivas_gerencial?: number | null;
}

export interface MetasFixas {
  meta_velocidade_virando?: number | null;
  meta_velocidade_com_acerto?: number | null;
  meta_tempo_medio_acerto?: number | null;
  meta_improdutivo_area_pct?: number | null;
  meta_improdutivo_gerencial_pct?: number | null;
}

export interface MetaEquipamento {
  equipamento: string;
  area: string;
  velocidade_limite: number;
}

export interface MetaMaquina {
  nome_maquina: string;
  meta_velocidade_virando?: number | null;
  meta_velocidade_com_acerto?: number | null;
  meta_tempo_medio_acerto?: number | null;
  meta_improdutivo_area_pct?: number | null;
  meta_improdutivo_gerencial_pct?: number | null;
}

export interface Classificacao {
  id: number | string;
  chave: string;
  tipo_apontam: string;
  motivo?: string | null;
  classificacao_perda: string;
  atuacao: string;
  nivel_atuacao?: string | null;
  qtd_apontamentos?: number | null;
  chave_duplicada?: boolean;
}

export interface ClassificacaoOrfa {
  tipo_apontam: string;
  motivo?: string | null;
  areas?: string | null;
  maquinas?: string | null;
  qtd_apontamentos?: number | null;
  horas?: number | null;
}

export interface AdminUser {
  id?: string;
  user_id?: string;
  full_name?: string;
  email?: string;
  role?: string;
  user_role?: string;
}

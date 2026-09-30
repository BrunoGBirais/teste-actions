import { ExternalLink } from "lucide-react";
import type { ProductCard } from "../../types/chat";

function Cell({ label, value, extraClass }: { label: string; value?: string; extraClass?: string }) {
  if (!value) return null;
  return (
    <div className="product-card-cell">
      <span className="product-card-cell-label">{label}</span>
      <span className={`product-card-cell-value${extraClass ? " " + extraClass : ""}`}>{value}</span>
    </div>
  );
}

export function ProductCards({ products }: { products: ProductCard[] }) {
  return (
    <div className="product-cards">
      {products.map((p, idx) => (
        <div className="product-card" key={idx}>
          <div className="product-card-header">
            <h4 className="product-card-title">{p.nome}</h4>
            {p.codigo && <span className="product-card-code">{p.codigo}</span>}
          </div>
          <div className="product-card-grid">
            <Cell label="Tamanho" value={p.tamanho} />
            <Cell label="Peso" value={p.peso} />
            <Cell label="Material" value={p.material} />
            <Cell label="Acabamento" value={p.acabamento} />
            <Cell label="Linha" value={p.linha} />
          </div>
          {p.link && (
            <div className="product-card-actions">
              <a className="product-card-link" href={p.link} target="_blank" rel="noopener noreferrer">
                <ExternalLink style={{ width: 14, height: 14 }} />
                <span>Ver no site</span>
              </a>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

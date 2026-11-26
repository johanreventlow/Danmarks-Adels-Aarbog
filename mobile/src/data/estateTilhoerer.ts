// Kort tekstlinje under godsets navn (#471, som web): »Hørte under <majorat> (<periode>)« på en gård,
// »Omfattede: <gårde>« på et majorat. Tom streng, når der intet er.
import type { EstateDetalje } from './types';

export function tilhoererLinje(e: Pick<EstateDetalje, 'hoererUnder' | 'omfattede'>): string {
  if (e.omfattede.length) return `Omfattede: ${e.omfattede.map((g) => g.navn).join(', ')}`;
  return e.hoererUnder
    .map((h) => `Hørte under ${h.navn}${h.periode ? ` ${h.periode.startsWith('(') ? h.periode : `(${h.periode})`}` : ''}`)
    .join(' · ');
}

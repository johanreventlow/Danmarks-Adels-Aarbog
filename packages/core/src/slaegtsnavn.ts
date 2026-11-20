// Slægtsnavn som helt ord til sidst i et navn (#401). Ingiftes navn er det fulde navn (»Anna Hansen«); når fødenavnet
// »Hansen« vises for sig (præsenslistens »født …«, profilens faktaliste), må det ikke stå dobbelt. Sammenligningen
// ignorerer store bogstaver og bindestregs-tegn (‐ ‑ ‒ – som -).
const normBindestreg = (s: string): string => s.replace(/[‐‑‒–]/g, '-').toLowerCase();

export function slutterPaaSlaegtsnavn(navn: string, slaegtsnavn: string): boolean {
  const s = slaegtsnavn.trim();
  return s !== '' && normBindestreg(navn.trim()).endsWith(` ${normBindestreg(s)}`);
}

// Navnet uden slægtsnavnet til sidst; står der intet andet tilbage, bevares navnet.
export function udenSlaegtsnavnTilSidst(navn: string, slaegtsnavn: string): string {
  if (!slutterPaaSlaegtsnavn(navn, slaegtsnavn)) return navn;
  const n = navn.trim();
  return n.slice(0, n.length - slaegtsnavn.trim().length).trim() || navn;
}

// Personer med mindst ét gæste-synligt billede, til forsidens minimumskrav (spec 2026-11-24-billeder-2018-20-design.md,
// trin 4; krav 8 i 2026-11-24-forside-minimumskrav-design.md). Ren funktion uden den env-bundne klient, så udpak.ts kan
// bruge den; browserens hentning ligger i personerMedBilledeFeed.ts, den rå hentning i forside/kilder.ts.
export function buildPersonerMedBillede(raa: readonly string[], canon: Record<string, string>): ReadonlySet<string> {
  return new Set(raa.map((id) => canon[id] ?? id));
}

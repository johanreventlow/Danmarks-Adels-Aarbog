// Personens viste navn i læserfladen (web + mobil). Et navn fra cachen (visning_fuldt_navn, ellers visning_navn)
// vises uændret; blank tekst tæller som manglende. Uden navn skelnes barn fra andre: bogen kan selv nævne et barn
// uden navn (DAA 1939 s. 37: »5. (?)«, person 1780), og »Unavngivet barn« siger det mere ærligt end »(uden navn)«.
// Ren visningsregel (#388): der skrives ingen påstand, og visning_navn forbliver NULL (invariant 4).
export const UDEN_NAVN = '(uden navn)';
export const UNAVNGIVET_BARN = 'Unavngivet barn';

// Alle family_member-roller, der gør personen til barn i familien (schema.sql, family_member.rolle).
export const BARN_ROLLER = ['barn', 'adopteret_barn', 'plejebarn', 'stedbarn'] as const;

const ikkeBlank = (v: string | null | undefined): v is string => v != null && v.trim() !== '';

export function personVisningsnavn(
  p: { visning_fuldt_navn?: string | null; visning_navn?: string | null },
  erBarn: boolean,
): string {
  if (ikkeBlank(p.visning_fuldt_navn)) return p.visning_fuldt_navn;
  if (ikkeBlank(p.visning_navn)) return p.visning_navn;
  return erBarn ? UNAVNGIVET_BARN : UDEN_NAVN;
}

// Person-id'er (som streng), der er barn i mindst én familie.
export function boernIder(members: { person_id: number | string; rolle: string | null }[]): Set<string> {
  const roller: readonly string[] = BARN_ROLLER;
  return new Set(members.filter((m) => roller.includes(String(m.rolle ?? '').toLowerCase())).map((m) => String(m.person_id)));
}

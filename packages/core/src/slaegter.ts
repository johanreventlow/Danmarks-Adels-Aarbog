export type SlaegtLabel = { navn: string };

export type SlaegtMembership = {
  membershipKind: 'agnatic' | 'cognatic' | 'adopted' | 'editorial';
};

export type LineageLabelContext = {
  slaegtNavn: string;
  canonicalLabel: string;
  schemeLabel?: string;
  ambiguous: boolean;
};

/** Kildenummerering er kun unik inden for sit scheme — aldrig globalt. */
export function lineageSchemeEntryKey(schemeId: string, code: string): string {
  return `${schemeId}:${code}`;
}

/** Vis den kanoniske lineage og kun den nødvendige kilde-/slægtskontekst. */
export function formatLineageLabel(context: LineageLabelContext): string {
  const base = context.ambiguous
    ? `${context.slaegtNavn} · ${context.canonicalLabel}`
    : context.canonicalLabel;
  return context.schemeLabel ? `${base} (${context.schemeLabel})` : base;
}

/** Indgiftethed er ikke slægtsmedlemskab og giver derfor aldrig afledt efternavn. */
export function surnameFromSlaegtMembership(
  slaegt: SlaegtLabel,
  membership: SlaegtMembership | null,
): string | null {
  return membership ? slaegt.navn : null;
}

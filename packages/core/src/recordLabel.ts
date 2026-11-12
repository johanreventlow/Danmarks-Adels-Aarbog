// Trin 6e-1: tekniske postnøgler (record-<uuid>, legacy-source:…) er interne og må aldrig vises i læseren.
const TEKNISK_RECORD = /^record-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function visbarPostEtiket(label: string | null | undefined): string | null {
  const t = label?.trim();
  if (!t) return null;
  if (TEKNISK_RECORD.test(t) || t.startsWith('legacy-source:')) return null;
  return t;
}

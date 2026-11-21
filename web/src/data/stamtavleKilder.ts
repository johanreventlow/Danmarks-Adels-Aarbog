export function byggErStamtavle(
  lineageRows: readonly { source_id: number | string; kode: string | null; slaegt_id?: number | string | null }[],
  schemes: readonly { slaegt_id: number | string; source_id: number | string | null; kind: string }[],
): (sourceId: string, linje: string) => boolean {
  const noegle = (sourceId: string, kode: string) => JSON.stringify([sourceId, kode]);
  const slaegtByLinje = new Map<string, string>();
  for (const l of lineageRows) {
    if (l.kode != null && l.slaegt_id != null) slaegtByLinje.set(noegle(String(l.source_id), l.kode), String(l.slaegt_id));
  }
  const kildeStamtavle = new Map<string, boolean>();
  const slaegtStamtavle = new Map<string, boolean>();
  for (const s of schemes) {
    if (s.source_id == null) continue;
    const sid = String(s.source_id);
    const k = noegle(sid, String(s.slaegt_id));
    kildeStamtavle.set(sid, kildeStamtavle.get(sid) === true || s.kind === 'stamtavle');
    slaegtStamtavle.set(k, slaegtStamtavle.get(k) === true || s.kind === 'stamtavle');
  }
  return (sourceId, linje) => {
    const slaegt = slaegtByLinje.get(noegle(sourceId, linje));
    return (slaegt == null ? undefined : slaegtStamtavle.get(noegle(sourceId, slaegt)))
      ?? kildeStamtavle.get(sourceId) ?? true;
  };
}

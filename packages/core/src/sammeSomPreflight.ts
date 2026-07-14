// Rådgivende pre-flight for redaktionel samme_som-linking (spec 2026-07-02 §6). Kører collapse med
// den hypotetiske kant på REDAKTIONS-datasættet og rapporterer om kantens komponent ville blive
// karantæneret (køn/levetid/konkurrerende forældre). IKKE autoritativt — offentlig visning kan afvige
// pga. RLS/completeness; DB-triggeren håndhæver graf-invarianterne. Kun et UI-hint.
import { collapseSameAs } from './collapseSameAs';
import type { Db, SameAsEdge } from './types';

export function previewSammeSom(
  rawDb: Db,
  existingEdges: SameAsEdge[],
  hypotetisk: SameAsEdge,
): { folder: boolean; grund: string | null } {
  const r = collapseSameAs(rawDb, [...existingEdges, hypotetisk], new Map());
  const karantæne = r.quarantined.find(
    (q) => q.members.includes(hypotetisk.alias) || q.members.includes(hypotetisk.canonical),
  );
  return karantæne ? { folder: false, grund: karantæne.reason } : { folder: true, grund: null };
}

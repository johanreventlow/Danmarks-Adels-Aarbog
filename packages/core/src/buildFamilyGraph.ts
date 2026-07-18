// Ren aggregering: family_member-rækker (family_id, person_id, rolle) → unions + parentChild.
// Delt byggesten for identitets-graf-validering (samme_som-preflight i redaktionen). IKKE brugt af
// den offentlige visnings-sti — web/src/data/model.ts har sin egen inline udgave med
// far-før-mor-ordinal-sortering til DISPLAY-rækkefølge, som denne bevidst ikke gengiver:
// rækkefølgen af p1/p2 har ingen betydning for collapseSameAs' konkurrerende-forældre-tjek.
import type { Union, ParentChild } from './types';

export type RawFamilyMember = {
  family_id: number | string;
  person_id: number | string;
  rolle: string | null;
};

const PARTNER_ROLLER = ['partner'];
const BARN_ROLLE = 'barn';

export function buildFamilyGraph(members: RawFamilyMember[]): { unions: Union[]; parentChild: ParentChild[] } {
  const byFam = new Map<string, RawFamilyMember[]>();
  for (const m of members) {
    const k = String(m.family_id);
    const arr = byFam.get(k);
    if (arr) arr.push(m); else byFam.set(k, [m]);
  }
  const unions: Union[] = [];
  const parentChild: ParentChild[] = [];
  for (const [fid, mem] of byFam) {
    const parents = mem.filter((m) => PARTNER_ROLLER.includes(String(m.rolle ?? '').toLowerCase()));
    const children = mem.filter((m) => String(m.rolle ?? '').toLowerCase() === BARN_ROLLE);
    if (parents.length) {
      unions.push({
        id: 'f' + fid,
        p1: String(parents[0].person_id),
        p2: parents[1] ? String(parents[1].person_id) : null,
        p2_name: null,
        year: null,
      });
    }
    for (const c of children) {
      for (const pa of parents) {
        parentChild.push({ child: String(c.person_id), parent: String(pa.person_id), union: 'f' + fid });
      }
    }
  }
  return { unions, parentChild };
}

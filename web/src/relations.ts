import { supabase } from "./supabase";

// Minimal person-visning til relations-grafen.
export interface RelPerson {
  id: number;
  visning_navn: string | null;
  visning_titel: string | null;
  visning_foedt: string | null;
  visning_doed: string | null;
  koen: string | null;
  linje?: string | null;
  nr?: number | null;
  konfidens?: string | null; // på family_member-linket (sikker/formodet/...)
}

export interface Relations {
  person: RelPerson;
  parents: RelPerson[];
  siblings: RelPerson[];
  spouses: RelPerson[];
  children: RelPerson[];
}

const PERSON_COLS = "id, visning_navn, visning_titel, visning_foedt, visning_doed, koen";

// Slå person-id op fra bogens (linje, nr).
export async function resolvePersonId(linje: string, nr: number): Promise<number> {
  const { data, error } = await supabase
    .from("person_external_id")
    .select("person_id")
    .eq("linje", linje)
    .eq("nr", nr)
    .limit(1)
    .single<{ person_id: number }>();
  if (error) throw error;
  return data.person_id;
}

// Find en persons nærmeste (forældre, søskende, ægtefæller, børn) via family/
// family_member. Slægtskab går GENNEM familie-enheden: man er 'barn' i sin
// fødselsfamilie og 'partner' i sin egen union.
export async function getRelations(personId: number): Promise<Relations> {
  const { data: me, error: meErr } = await supabase
    .from("person")
    .select(PERSON_COLS)
    .eq("id", personId)
    .single<RelPerson>();
  if (meErr) throw meErr;

  // mine medlemskaber: hvilke familier, og i hvilken rolle
  const { data: myMems, error: mmErr } = await supabase
    .from("family_member")
    .select("family_id, rolle")
    .eq("person_id", personId)
    .returns<{ family_id: number; rolle: string }[]>();
  if (mmErr) throw mmErr;

  const birthFams = new Set((myMems ?? []).filter((m) => m.rolle === "barn").map((m) => m.family_id));
  const unionFams = new Set((myMems ?? []).filter((m) => m.rolle === "partner").map((m) => m.family_id));
  const allFamIds = [...new Set([...birthFams, ...unionFams])];
  if (allFamIds.length === 0) {
    return { person: me, parents: [], siblings: [], spouses: [], children: [] };
  }

  // alle medlemmer af de relevante familier
  const { data: members, error: memErr } = await supabase
    .from("family_member")
    .select("family_id, person_id, rolle, konfidens")
    .in("family_id", allFamIds)
    .returns<{ family_id: number; person_id: number; rolle: string; konfidens: string | null }[]>();
  if (memErr) throw memErr;

  const memberList = members ?? [];
  const otherIds = [...new Set(memberList.map((m) => m.person_id).filter((id) => id !== personId))];

  // person-detaljer + bogens (linje, nr) for de relaterede
  const pById = new Map<number, RelPerson>();
  if (otherIds.length) {
    const { data: persons } = await supabase.from("person").select(PERSON_COLS).in("id", otherIds).returns<RelPerson[]>();
    for (const p of persons ?? []) pById.set(p.id, p);
    const { data: extids } = await supabase
      .from("person_external_id")
      .select("person_id, linje, nr")
      .in("person_id", otherIds)
      .returns<{ person_id: number; linje: string | null; nr: number | null }[]>();
    for (const e of extids ?? []) {
      const p = pById.get(e.person_id);
      if (p && p.linje == null) { p.linje = e.linje; p.nr = e.nr; }
    }
  }

  const pick = (famSet: Set<number>, rolle: string): RelPerson[] => {
    const seen = new Set<number>();
    const out: RelPerson[] = [];
    for (const m of memberList) {
      if (!famSet.has(m.family_id) || m.rolle !== rolle || m.person_id === personId) continue;
      if (seen.has(m.person_id)) continue;
      const p = pById.get(m.person_id);
      if (p) { seen.add(m.person_id); out.push({ ...p, konfidens: m.konfidens }); }
    }
    return out;
  };

  return {
    person: me,
    parents: pick(birthFams, "partner"),
    siblings: pick(birthFams, "barn"),
    spouses: pick(unionFams, "partner"),
    children: pick(unionFams, "barn"),
  };
}

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
  vielse?: string | null;    // vielsesdato(er) fra familiens vielse-fakta (kun ægtefæller)
  skilt?: boolean;           // familien har skilsmisse-fakta
  note?: string | null;      // gift-ind ægtefælles bio (forældre/fødsel/dåb) fra familie-note
}

export interface Relations {
  person: RelPerson;
  parents: RelPerson[];
  siblings: RelPerson[];
  spouses: RelPerson[];
  children: RelPerson[];
}

const PERSON_COLS = "id, visning_navn, visning_titel, visning_foedt, visning_doed, koen";

export interface FactRow { faktatype: string; vaerdi: string | null; dato: string | null; }
export interface PersonDetail { facts: FactRow[]; notes: string[]; narrative: string | null; }

// Fokus-personens lagdelte fakta (via konklusion) + den fulde narrativ-prosa.
// Den dybe biografi (dåb, uddannelse, karriere…) ligger i narrativen — kun
// rygrads-fakta er struktureret (datamodel §6).
export async function getPersonDetail(personId: number): Promise<PersonDetail> {
  const { data: facts } = await supabase
    .from("fact").select("id, faktatype")
    .eq("subjekt_type", "person").eq("subjekt_id", personId)
    .returns<{ id: number; faktatype: string }[]>();
  const factList = facts ?? [];
  const ids = factList.map((f) => f.id);

  let rows: FactRow[] = [];
  if (ids.length) {
    const { data: concs } = await supabase
      .from("conclusion").select("target_id, valgt_assertion_id")
      .eq("target_type", "fact").in("target_id", ids)
      .returns<{ target_id: number; valgt_assertion_id: number | null }[]>();
    const chosen = new Map<number, number>();
    for (const c of concs ?? []) if (c.valgt_assertion_id != null) chosen.set(c.target_id, c.valgt_assertion_id);
    const aIds = [...new Set(chosen.values())];
    const aById = new Map<number, { vaerdi_tekst: string | null; date_raw: string | null }>();
    if (aIds.length) {
      const { data: asserts } = await supabase
        .from("assertion").select("id, vaerdi_tekst, date_raw").in("id", aIds)
        .returns<{ id: number; vaerdi_tekst: string | null; date_raw: string | null }[]>();
      for (const a of asserts ?? []) aById.set(a.id, a);
    }
    rows = factList
      .filter((f) => f.faktatype !== "navn") // navn vises i kortets titel
      .map((f) => {
        const a = aById.get(chosen.get(f.id) ?? -1);
        return { faktatype: f.faktatype, vaerdi: a?.vaerdi_tekst ?? null, dato: a?.date_raw ?? null };
      });
  }

  const { data: nn } = await supabase
    .from("note").select("indhold")
    .eq("target_type", "person").eq("target_id", personId)
    .returns<{ indhold: string | null }[]>();
  const notes = (nn ?? []).map((n) => n.indhold).filter((x): x is string => !!x);

  const { data: narr } = await supabase
    .from("narrative").select("tekst")
    .eq("subjekt_type", "person").eq("subjekt_id", personId)
    .returns<{ tekst: string }[]>();
  const narrative = (narr ?? []).map((n) => n.tekst).join("\n\n") || null;
  return { facts: rows, notes, narrative };
}

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

  // ægteskabs-fakta (vielse/skilsmisse) for union-familier — vielse/skilsmisse er
  // FAMILIE-fakta, ikke person-fakta, så de hentes separat og hæftes på ægtefællen.
  const marrByFam = new Map<number, { vielse: string | null; skilt: boolean }>();
  const unionIds = [...unionFams];
  if (unionIds.length) {
    const { data: ff } = await supabase
      .from("fact").select("id, subjekt_id, faktatype")
      .eq("subjekt_type", "family").in("subjekt_id", unionIds).in("faktatype", ["vielse", "skilsmisse"])
      .returns<{ id: number; subjekt_id: number; faktatype: string }[]>();
    const fl = ff ?? [];
    for (const f of fl) {
      const m = marrByFam.get(f.subjekt_id) ?? { vielse: null, skilt: false };
      if (f.faktatype === "skilsmisse") m.skilt = true;
      marrByFam.set(f.subjekt_id, m);
    }
    const vIds = fl.filter((f) => f.faktatype === "vielse").map((f) => f.id);
    if (vIds.length) {
      const { data: cc } = await supabase.from("conclusion").select("target_id, valgt_assertion_id")
        .eq("target_type", "fact").in("target_id", vIds).returns<{ target_id: number; valgt_assertion_id: number | null }[]>();
      const aMap = new Map<number, number>();
      for (const c of cc ?? []) if (c.valgt_assertion_id != null) aMap.set(c.target_id, c.valgt_assertion_id);
      const aIds = [...new Set(aMap.values())];
      if (aIds.length) {
        const { data: aa } = await supabase.from("assertion").select("id, date_raw").in("id", aIds).returns<{ id: number; date_raw: string | null }[]>();
        const dr = new Map<number, string | null>(); for (const a of aa ?? []) dr.set(a.id, a.date_raw);
        for (const f of fl) if (f.faktatype === "vielse") { const m = marrByFam.get(f.subjekt_id); if (m) m.vielse = dr.get(aMap.get(f.id) ?? -1) ?? m.vielse; }
      }
    }
  }

  // familie-noter for union-familier — gift-ind ægtefælles bio står typisk her
  // (forældre/fødsel/dåb/erhverv), da hun ikke har egen post i stamtavlen.
  const noteByFam = new Map<number, string>();
  if (unionIds.length) {
    const { data: nn } = await supabase.from("note").select("target_id, indhold")
      .eq("target_type", "family").in("target_id", unionIds)
      .returns<{ target_id: number; indhold: string | null }[]>();
    for (const n of nn ?? []) if (n.indhold && !/^partner ekstern ref:/i.test(n.indhold)) {
      const prev = noteByFam.get(n.target_id);
      noteByFam.set(n.target_id, prev ? `${prev}\n${n.indhold}` : n.indhold);
    }
  }

  // ægtefæller med vielse/skilsmisse + bio-note hæftet på (beholder family_id-konteksten)
  const spouses: RelPerson[] = [];
  const seenSp = new Set<number>();
  for (const m of memberList) {
    if (!unionFams.has(m.family_id) || m.rolle !== "partner" || m.person_id === personId || seenSp.has(m.person_id)) continue;
    const p = pById.get(m.person_id); if (!p) continue;
    seenSp.add(m.person_id);
    const marr = marrByFam.get(m.family_id);
    spouses.push({ ...p, konfidens: m.konfidens, vielse: marr?.vielse ?? null, skilt: marr?.skilt ?? false, note: noteByFam.get(m.family_id) ?? null });
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
    spouses,
    children: pick(unionFams, "barn"),
  };
}

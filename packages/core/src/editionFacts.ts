// 6e-1 (spec 2026-11-12-trin6e-laeserflade-design.md §5.1-5.4): fakta for en foldet person vist pr. bogudgave.
// Hver oplysning står én gang i den valgte udgaves egne ord; den anden udgave nævnes som note (»✓ også i …«,
// »… skriver: …«) eller samles under »Kun i …«. Projektets værste fejl er et falsk »✓ også« eller en udgaves
// oplysning, der forsvinder uden spor — derfor: konservativ lighed, og alt fra en anden udgave, som ingen note
// dækker, går til kunI.
import {
  FAKTA_UDELADT,
  factSource,
  factValue,
  typeRank,
  type PersonFactSource,
  type PersonFactStatement,
  type PublicPersonFactRow,
} from './personFacts';
import { ENKELTVAERDI_TYPER, erTomFaktaVaerdi, faktaVaerdierEns, normaliserFaktaVaerdi } from './factEquality';
import { erRelativDato, oploesRelativDato } from './relativeDates';

export type Udgave = { sourceId: string; label: string; aar: number | null };
export type UdgaveFaktaInput = {
  rows: PublicPersonFactRow[];
  udgaver: Udgave[]; // kun source.slags = 'DAA-udgave'
  udgaveForPersonRaekke: Record<string, string>; // person_id → sourceId fra ekstern nøgle
  fritekstKilde: Record<string, string[]>; // assertion_id → alle citat_tekst for citationer uden source_id
  slukketEnighed?: ReadonlySet<string>; // faktatyper uden »✓ også« (spec §5.4)
};
export type UdgaveNote =
  | { art: 'enig'; udgave: Udgave }
  | { art: 'skriver'; udgave: Udgave; vaerdier: string[] };
export type UdgaveFaktaLinje = {
  noegle: string;
  faktatype: string;
  vaerdi: string; // '' for et omstridt faktum uden valgt påstand; udsagnene står da i `andre`
  kilder: PersonFactSource[];
  omstridt: boolean;
  andre: PersonFactStatement[];
  noter: UdgaveNote[];
};
export type KunIUdgave = { udgave: Udgave; faktatype: string; vaerdier: string[] };
export type UdgaveFaktaVisning = { linjer: UdgaveFaktaLinje[]; kunI: KunIUdgave[] };

// ---- intern model ----

type Paastand = { assertionId: string; rows: PublicPersonFactRow[]; value: string; chosen: boolean; bundet: boolean };

// Et faktums visning i sin egen udgave (§5.2).
//  - 'egen': den viste påstand er udgavens egen → får noter og indgår i andre udgavers noter.
//  - 'som-i-dag': ingen udgaveegen påstand (redaktørfaktum) eller ingen udgave → vises, men aldrig i noter.
//  - 'uden-valg': ingen vist værdi (omstridt uden valg, eller tomt valg med andre udsagn) → vaerdi '' og alt i
//    `andre`; i andre udgaver tæller udgavens EGNE udsagn (`usikre`) som »skriver«, aldrig som ✓.
type FaktumVisning = {
  factId: string;
  personId: string;
  reference?: string | null; // dåb/begravelse: den viste fødsel/død, opløsningen brugte
  faktatype: string;
  udgave: string | null;
  art: 'egen' | 'som-i-dag' | 'uden-valg';
  omstridt: boolean;
  vaerdi: string;
  kilder: PersonFactSource[];
  andre: PersonFactStatement[];
  usikre: string[];
};

const unikkeRaekker = (rows: PublicPersonFactRow[]) => {
  const seen = new Set<string>();
  return rows.filter((r) => {
    const k = JSON.stringify(r);
    if (seen.has(k)) return false; // samme række fra flere medlems-id'er
    seen.add(k);
    return true;
  });
};

const sorterUdgaver = (udgaver: Udgave[]) =>
  udgaver
    .map((u, i) => ({ u, i }))
    .sort((a, b) => (a.u.aar === b.u.aar ? a.i - b.i : a.u.aar == null ? 1 : b.u.aar == null ? -1 : b.u.aar - a.u.aar))
    .map((x) => x.u);

const statement = (r: PublicPersonFactRow): PersonFactStatement => ({
  assertionId: String(r.assertion_id), value: factValue(r), source: factSource(r),
});

const unikkeEfterLabel = (kilder: PersonFactSource[]) => {
  const seen = new Set<string>();
  return kilder.filter((k) => (seen.has(k.label) ? false : (seen.add(k.label), true)));
};

const unikkeUdsagn = (st: PersonFactStatement[]) => {
  const seen = new Set<string>();
  return st.filter((s) => {
    const k = `${s.assertionId}\u0000${s.source.label}`;
    return seen.has(k) ? false : (seen.add(k), true);
  });
};

// Distinkte værdier efter lighedsreglen, i første-set-rækkefølge.
const distinkte = (faktatype: string, vaerdier: string[]) => {
  const ud: string[] = [];
  for (const v of vaerdier) if (!ud.some((u) => faktaVaerdierEns(faktatype, u, v))) ud.push(v);
  return ud;
};

export function udgaveForRaekker(input: UdgaveFaktaInput): Record<string, string | null> {
  const kendte = new Set(input.udgaver.map((u) => u.sourceId));
  const citerede = new Map<string, Set<string>>();
  for (const r of input.rows) {
    const pid = String(r.person_id);
    const s = citerede.get(pid) ?? new Set<string>();
    if (r.source_id != null && kendte.has(String(r.source_id))) s.add(String(r.source_id));
    citerede.set(pid, s);
  }
  const ud: Record<string, string | null> = {};
  for (const [pid, s] of citerede) {
    const ext = input.udgaveForPersonRaekke[pid];
    // ekstern nøgle først; ellers den ene DAA-udgave, rækkens citationer peger på; ellers null (vises i alle)
    ud[pid] = ext != null && kendte.has(ext) ? ext : s.size === 1 ? [...s][0] : null;
  }
  return ud;
}

// Er påstanden udgavens egen (§5.2)? Bundet til udgavens post, citation til udgaven, eller en fritekstkilde,
// hvor ALLE tekster nævner netop denne udgave og ingen anden (tom liste eller modstrid → nej).
// En binding til en ANDEN udgaves post tæller ikke: så ville den udgave bekræfte sig selv (§5.1).
function erEgen(p: Paastand, udgave: Udgave, input: UdgaveFaktaInput): boolean {
  const andenUdgave = (r: PublicPersonFactRow) =>
    r.source_id != null && String(r.source_id) !== udgave.sourceId && input.udgaver.some((u) => u.sourceId === String(r.source_id));
  if (p.rows.some((r) => r.record_ref && !andenUdgave(r))) return true;
  if (p.rows.some((r) => r.source_id != null && String(r.source_id) === udgave.sourceId)) return true;
  if (!p.rows.some((r) => r.source_id == null)) return false;
  const tekster = input.fritekstKilde[p.assertionId] ?? [];
  const andre = input.udgaver.filter((u) => u.sourceId !== udgave.sourceId);
  return tekster.length > 0
    && tekster.every((t) => t.includes(udgave.label) && !andre.some((u) => t.includes(u.label)));
}

// Alle fakta med deres visning i egen udgave, i buildPersonFacts' orden (typeorden, date_min, fact_id), med relative
// datoer opløst. `udenUdgaver`: valgt = null → alt som én udgave, valgt påstand som i dag.
const fakta = (input: UdgaveFaktaInput, udenUdgaver: boolean) => oploesRelative(faktaRaa(input, udenUdgaver));

function faktaRaa(input: UdgaveFaktaInput, udenUdgaver: boolean): FaktumVisning[] {
  const raekkeUdgave = udenUdgaver ? {} : udgaveForRaekker(input);
  const udgaveMap = new Map(input.udgaver.map((u) => [u.sourceId, u]));
  const byFact = new Map<string, PublicPersonFactRow[]>();
  for (const r of unikkeRaekker(input.rows)) {
    if (FAKTA_UDELADT.includes(r.faktatype)) continue;
    const k = String(r.fact_id);
    const g = byFact.get(k);
    if (g) g.push(r);
    else byFact.set(k, [r]);
  }

  const ordnet = [...byFact.values()].sort((ra, rb) => {
    const a = ra[0], b = rb[0];
    return typeRank(a.faktatype) - typeRank(b.faktatype)
      || (a.date_min === b.date_min ? 0 : a.date_min == null ? 1 : b.date_min == null ? -1 : a.date_min < b.date_min ? -1 : 1)
      || Number(a.fact_id) - Number(b.fact_id);
  });

  const ud: FaktumVisning[] = [];
  for (const rs of ordnet) {
    const first = rs[0];
    const udgaveId = udenUdgaver ? null : (raekkeUdgave[String(first.person_id)] ?? null);
    const udgave = udgaveId == null ? undefined : udgaveMap.get(udgaveId);

    // én påstand pr. assertion (rækkerne er én pr. påstand × citation)
    const paastande = new Map<string, Paastand>();
    for (const r of rs) {
      const k = String(r.assertion_id);
      const p = paastande.get(k);
      if (p) {
        p.rows.push(r);
        p.chosen ||= r.chosen;
        p.bundet ||= !!r.record_ref;
      } else {
        paastande.set(k, { assertionId: k, rows: [r], value: factValue(r), chosen: r.chosen, bundet: !!r.record_ref });
      }
    }
    const alle = [...paastande.values()];
    const valgt = alle.find((p) => p.chosen);
    const base = { factId: String(first.fact_id), personId: String(first.person_id), faktatype: first.faktatype, udgave: udgaveId,
      omstridt: first.conclusion_status === 'omstridt' };
    const ikkeTomme = (ps: Paastand[]) => ps.flatMap((p) => p.rows.map(statement)).filter((s) => !erTomFaktaVaerdi(s.value));

    // Udgavens egne, ikke-tomme udsagn blandt ps — kun de kan indgå i en anden udgaves noter.
    const egneVaerdier = (ps: Paastand[]) =>
      udgave ? ikkeTomme(ps.filter((p) => erEgen(p, udgave, input))).map((s) => s.value) : [];
    const udenVaerdi = (andre: PersonFactStatement[], usikre: string[]) => {
      if (andre.length) ud.push({ ...base, art: usikre.length ? 'uden-valg' : 'som-i-dag', vaerdi: '', kilder: [], andre, usikre });
    };

    if (!valgt) {
      udenVaerdi(ikkeTomme(alle), egneVaerdier(alle));
      continue;
    }

    let vist = valgt;
    let art: FaktumVisning['art'] = 'som-i-dag';
    if (udgave) {
      if (erEgen(valgt, udgave, input)) art = 'egen';
      else {
        const alternativ = alle
          // et tomt alternativ må ikke sluge redaktørens ikke-tomme valg → så vises valget som i dag
          .filter((p) => p !== valgt && !erTomFaktaVaerdi(p.value) && erEgen(p, udgave, input))
          .sort((a, b) => Number(b.bundet) - Number(a.bundet) || Number(a.assertionId) - Number(b.assertionId)
            || (a.assertionId < b.assertionId ? -1 : a.assertionId > b.assertionId ? 1 : 0))[0];
        if (alternativ) {
          vist = alternativ;
          art = 'egen';
        }
      }
    }
    // Andre udsagn = øvrige påstande, men ikke et tilsidesat redaktørvalg uden udgavens egen kilde: redaktionens
    // valg ses kun i navnet øverst, uden markering (§5.2, projektejeren 2026-11-12).
    const oevrige = alle.filter((p) => p !== vist && !(vist !== valgt && p === valgt));
    const andre = ikkeTomme(oevrige);
    if (erTomFaktaVaerdi(vist.value)) {
      // Tom vist værdi: ingen linje — medmindre faktummet har andre, ikke-tomme udsagn; de må ikke forsvinde.
      // De vises som ved omstridt uden valg (vaerdi '', alt i `andre`) og tæller aldrig som ✓ i andre udgaver.
      udenVaerdi(andre, egneVaerdier(oevrige));
      continue;
    }
    ud.push({ ...base, art, vaerdi: vist.value, kilder: unikkeEfterLabel(vist.rows.map(factSource)), andre, usikre: [] });
  }
  return ud;
}

// ---- relative datoer (§5.4a, afgørelse 12) ----

// Dåb opløses ud fra fødslen, begravelse ud fra døden — begge fra SAMME personrække (og dermed samme udgave).
const RELATIV_REFERENCE: Record<string, string> = { dåb: 'fødsel', begravelse: 'død' };
// Typer, hvor en (uopløst) relativ dato aldrig må give ✓. Navne o.l. er udeladt: »S. A.« kan være initialer.
const RELATIV_TYPER: ReadonlySet<string> = new Set(['dåb', 'begravelse', 'død', 'titel', 'dekoration']);
const uopløstRelativ = (faktatype: string, v: string) => RELATIV_TYPER.has(faktatype) && erRelativDato(v);

// Referencen er rækkens første viste fødsel/død i fakta-ordenen. Kan et led ikke opløses, vises bogens tekst —
// den forbliver relativ og kan derfor aldrig give ✓ (se `ens` i byggUdgaveFakta).
function oploesRelative(fs: FaktumVisning[]): FaktumVisning[] {
  const reference = new Map<string, string>();
  for (const f of fs) {
    const k = `${f.personId}\u0000${f.faktatype}`;
    if (f.vaerdi !== '' && !reference.has(k)) reference.set(k, f.vaerdi);
  }
  return fs.map((f) => {
    const refType = RELATIV_REFERENCE[f.faktatype];
    if (!refType) return f;
    const ref = reference.get(`${f.personId}\u0000${refType}`) ?? null;
    const opl = (v: string) => (erRelativDato(v) ? (oploesRelativDato(v, ref) ?? v) : v);
    return {
      reference: ref,
      ...f,
      vaerdi: opl(f.vaerdi),
      andre: f.andre.map((a) => ({ ...a, value: opl(a.value) })),
      usikre: f.usikre.map(opl),
    };
  });
}

type Linje = UdgaveFaktaLinje & { egen: boolean; norm: string | null };

function linjerFor(fs: FaktumVisning[]): Linje[] {
  const linjer: Linje[] = [];
  const ids = new Map<Linje, string[]>();
  for (const f of fs) {
    // tom linje og uopløst relativ dato sammenlægges aldrig (samme tekst kan betyde forskellige datoer)
    const norm = f.vaerdi === '' || uopløstRelativ(f.faktatype, f.vaerdi) ? null : normaliserFaktaVaerdi(f.faktatype, f.vaerdi);
    const hit = norm == null ? undefined : linjer.find((l) => l.faktatype === f.faktatype && l.norm === norm);
    if (hit) {
      // sammenlægning (§5.2): samme type og ens værdi → én linje, kilderne samlet
      hit.kilder = unikkeEfterLabel([...hit.kilder, ...f.kilder]);
      hit.andre = unikkeUdsagn([...hit.andre, ...f.andre]);
      hit.omstridt ||= f.omstridt;
      hit.egen ||= f.art === 'egen';
      ids.get(hit)!.push(f.factId);
      continue;
    }
    const l: Linje = {
      noegle: '', faktatype: f.faktatype, vaerdi: f.vaerdi, kilder: f.kilder, omstridt: f.omstridt,
      andre: unikkeUdsagn(f.andre), noter: [], egen: f.art === 'egen', norm,
    };
    linjer.push(l);
    ids.set(l, [f.factId]);
  }
  for (const l of linjer) l.noegle = `${l.faktatype}:${ids.get(l)!.join('+')}`;
  return linjer;
}

const offentlig = ({ egen: _e, norm: _n, ...l }: Linje): UdgaveFaktaLinje => l;

// En anden udgaves viste værdier af én type. `sikker` = viste værdi af et faktum med udgaveegen påstand;
// usikker = udsagn fra et omstridt faktum uden valg (tæller som »skriver«, aldrig som ✓).
type Pulje = { vaerdi: string; sikker: boolean }[];

function puljer(fs: FaktumVisning[], udgaveId: string): Map<string, Pulje> {
  const ud = new Map<string, Pulje>();
  for (const f of fs) {
    if (f.udgave !== udgaveId || f.art === 'som-i-dag') continue; // redaktørfakta indgår ikke i noter (§5.2)
    const p = ud.get(f.faktatype) ?? [];
    if (f.art === 'egen') p.push({ vaerdi: f.vaerdi, sikker: true });
    else for (const v of f.usikre) p.push({ vaerdi: v, sikker: false });
    ud.set(f.faktatype, p);
  }
  return ud;
}

export function udgaverMedFakta(input: UdgaveFaktaInput): string[] {
  const fs = fakta(input, false);
  return sorterUdgaver(input.udgaver).map((u) => u.sourceId).filter((id) => fs.some((f) => f.udgave === id));
}

export function byggUdgaveFakta(input: UdgaveFaktaInput, valgt: string | null): UdgaveFaktaVisning {
  if (valgt == null) {
    return { linjer: linjerFor(fakta(input, true)).map((l) => offentlig({ ...l, noter: [] })), kunI: [] };
  }
  const fs = fakta(input, false);
  // den valgte udgaves rækker + rækker uden entydig udgave (vises i alle, men sammenlignes aldrig)
  const linjer = linjerFor(fs.filter((f) => f.udgave === valgt || f.udgave == null));
  const slukket = input.slukketEnighed ?? new Set<string>();
  const kunI: KunIUdgave[] = [];

  for (const anden of sorterUdgaver(input.udgaver)) {
    if (anden.sourceId === valgt) continue;
    const pulje = puljer(fs, anden.sourceId);
    const typer = [...pulje.keys()].map((t, i) => ({ t, i }))
      .sort((a, b) => typeRank(a.t) - typeRank(b.t) || a.i - b.i).map((x) => x.t);
    for (const t of typer) {
      const p = pulje.get(t)!;
      if (!p.length) continue;
      const alle = distinkte(t, p.map((x) => x.vaerdi));
      const egne = linjer.filter((l) => l.egen && l.faktatype === t);
      // En uopløst relativ dato giver aldrig ✓ — hverken som linjen eller som den anden udgaves værdi (§5.4a).
      const ens = (l: Linje, x: { vaerdi: string; sikker: boolean }) => x.sikker
        && !uopløstRelativ(t, l.vaerdi) && !uopløstRelativ(t, x.vaerdi) && faktaVaerdierEns(t, l.vaerdi, x.vaerdi);
      for (const l of egne) {
        if (slukket.has(t)) l.noter.push({ art: 'skriver', udgave: anden, vaerdier: alle });
        else if (ENKELTVAERDI_TYPER.has(t)) {
          l.noter.push(p.every((x) => ens(l, x)) ? { art: 'enig', udgave: anden } : { art: 'skriver', udgave: anden, vaerdier: alle });
        } else if (p.some((x) => ens(l, x))) l.noter.push({ art: 'enig', udgave: anden });
      }
      // Dækket af noterne: enkeltværdi og slukket dækker alt, når der er en egen linje; flerværdi kun de parrede.
      const udaekket = !egne.length ? alle
        : slukket.has(t) || ENKELTVAERDI_TYPER.has(t) ? []
          : distinkte(t, p.filter((x) => !egne.some((l) => ens(l, x))).map((x) => x.vaerdi));
      if (udaekket.length) kunI.push({ udgave: anden, faktatype: t, vaerdier: udaekket });
    }
  }
  return { linjer: linjer.map(offentlig), kunI };
}

// Til målingen (tools/maal-6e1): hvert vist faktum, hvis viste værdi før opløsningen er en relativ dato, med
// personrækkens udgave, om core opløste det, og den reference, der blev brugt (kun dåb/begravelse).
export type RelativDatoStatus = {
  factId: string; faktatype: string; udgave: string | null; oploest: boolean; reference: string | null;
};
export function relativeDatoer(input: UdgaveFaktaInput): RelativDatoStatus[] {
  const raa = faktaRaa(input, false);
  const opl = oploesRelative(raa);
  return raa.flatMap((f, i) => (f.vaerdi !== '' && erRelativDato(f.vaerdi)
    ? [{ factId: f.factId, faktatype: f.faktatype, udgave: f.udgave, oploest: !erRelativDato(opl[i].vaerdi), reference: opl[i].reference ?? null }]
    : []));
}

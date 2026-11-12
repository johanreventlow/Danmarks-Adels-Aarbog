// 6e-1 plan-Task 5 (spec 2026-11-12-trin6e-laeserflade-design.md »plan-Task 0«): måler læserfladens fakta pr. udgave
// mod en LOKAL stand-in med den rigtige core-kode — ingen genimplementering af reglerne.
//
//   PGDATABASE=<stand-in> npx tsx tools/maal-6e1/maal.ts --ark <scratchpad>/6e1-stikproeve.html
//
// Kun læsning: SELECT og de offentlige læse-RPC'er. Stdout bærer kun tal og id'er; stikprøvearket (med værdier)
// skrives kun til --ark-stien, som skal ligge uden for repo'et.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import {
  buildFamilyGraph,
  byggUdgaveFakta,
  byggUdgaveVaelger,
  collapseSameAs,
  faktaVaerdierEns,
  fmtYears,
  mapPublicBioSourceVersionsV2,
  parseYear,
  udgaveForRaekker,
  udgaverMedFakta,
  type AppPerson,
  type PublicPersonFactRow,
  type Udgave,
  type UdgaveFaktaInput,
  type UdgaveFaktaVisning,
} from '../../packages/core/src/index';
import { factValue } from '../../packages/core/src/personFacts';

const REPO = path.resolve(__dirname, '..', '..');
const argv = process.argv.slice(2);
const arkIdx = argv.indexOf('--ark');
const ark = arkIdx >= 0 ? argv[arkIdx + 1] : undefined;
if (!ark) throw new Error('--ark <sti uden for repo> mangler');
const arkAbs = path.resolve(ark);
if (arkAbs === REPO || arkAbs.startsWith(REPO + path.sep)) throw new Error('--ark må ikke ligge i repo\'et (arket bærer værdier)');
if (!process.env.PGDATABASE) throw new Error('PGDATABASE mangler (stand-in)');

const t0 = performance.now();
const tider: [string, number][] = [];
const tid = (navn: string, start: number) => tider.push([navn, Math.round(performance.now() - start)]);

// psql som JSON; stderr udskrives aldrig (den kan citere rækker).
function q<T>(sql: string): T[] {
  let ud: string;
  try {
    ud = execFileSync('psql', ['-XAt', '-v', 'ON_ERROR_STOP=1', '-c', `select coalesce(json_agg(t), '[]'::json) from (${sql}) t`], {
      env: { ...process.env, PGOPTIONS: '-c default_transaction_read_only=on' }, maxBuffer: 512 * 1024 * 1024, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    throw new Error(`psql fejlede (exit ${(e as { status?: number }).status ?? '?'})`);
  }
  return JSON.parse(ud) as T[];
}

// ---- 1. Hent (som anon ser det: person_offentlig i db-rls.sql = levende false, ikke privat, ikke staged) ----
let s = performance.now();
type RawPerson = { id: number; visning_foedt: string | null; visning_doed: string | null; koen: string | null };
const personer = q<RawPerson>(`select id, visning_foedt, visning_doed, koen from person
  where levende = false and coalesce(privat, false) = false and coalesce(staged, false) = false order by id`);
const offentlige = new Set(personer.map((p) => String(p.id)));
const medlemmer = q<{ family_id: number; person_id: number; rolle: string | null }>(
  `select family_id, person_id, rolle from family_member order by family_id, person_id`,
).filter((m) => offentlige.has(String(m.person_id)));
const kanter = q<{ subjekt_id: number; objekt_id: number }>(`select r.subjekt_id, r.objekt_id from relation r
  where r.rolle = 'samme_som' and r.subjekt_type = 'person' and r.objekt_type = 'person'
    and exists (select 1 from conclusion c where c.target_type = 'relation' and c.target_id = r.id and c.status = 'afklaret')
  order by r.id`);
const kilder = q<{ id: number; udgave: string; aar: number | null }>(
  `select id, udgave, aar from source where slags = 'DAA-udgave' order by id`,
);
const koord = q<{ person_id: number; source_id: number }>(`select person_id, source_id from public.public_person_source_coordinates()`);
const ids = personer.map((p) => p.id);
const faktaRaekker = q<PublicPersonFactRow>(`select * from public.public_person_facts(array[${ids.join(',')}]::bigint[])`);
const bioRaekker = q<Record<string, unknown>>(`select * from public.public_person_bio_source_versions_v2(array[${ids.join(',')}]::bigint[])`);
// fritekstkilde (spec §5.2): citat_tekst for valgte påstande uden source_id
const valgteUdenKilde = [...new Set(faktaRaekker.filter((r) => r.chosen && r.source_id == null).map((r) => Number(r.assertion_id)))];
const citater = valgteUdenKilde.length
  ? q<{ assertion_id: number; citat_tekst: string | null }>(`select assertion_id, citat_tekst from citation
      where source_id is null and assertion_id in (${valgteUdenKilde.join(',')}) order by id`)
  : [];
// Afstemning af »de 17« redaktørpåstande (spec §5.1): alle personfakta-påstande med en citation uden source_id.
const redaktoer = q<{ assertion_id: number; person_id: number; faktatype: string; valgt: boolean; offentlig: boolean }>(`
  select a.id as assertion_id, f.subjekt_id as person_id, f.faktatype,
         coalesce(c.valgt_assertion_id = a.id, false) as valgt,
         (p.levende = false and coalesce(p.privat, false) = false and coalesce(p.staged, false) = false) as offentlig
  from fact f join assertion a on a.target_type = 'fact' and a.target_id = f.id
  left join conclusion c on c.target_type = 'fact' and c.target_id = f.id
  join person p on p.id = f.subjekt_id
  where f.subjekt_type = 'person' and f.faktatype not in ('forældrefamilie', 'forældre_ukendt')
    and exists (select 1 from citation ci where ci.assertion_id = a.id and ci.source_id is null)
  order by a.id`);
tid('hentning (psql + RPC)', s);

// ---- 2. Komponenter som klientens foldning (web/src/data/model.ts) ----
s = performance.now();
const appPersons: AppPerson[] = personer.map((p) => ({
  id: String(p.id), name: '', born: parseYear(p.visning_foedt), died: parseYear(p.visning_doed),
  years: fmtYears(p.visning_foedt, p.visning_doed), title: '', bio: '', privat: false,
  koen: p.koen === 'mand' || p.koen === 'kvinde' ? p.koen : null,
}));
const { unions, parentChild } = buildFamilyGraph(medlemmer);
// anon-policyen på relation (db-rls.sql) skjuler en kant, når et af endepunkterne ikke er offentligt → væk FØR foldning
const alleKanter = kanter.map((k) => ({ alias: String(k.subjekt_id), canonical: String(k.objekt_id) }));
const kantListe = alleKanter.filter((k) => offentlige.has(k.alias) && offentlige.has(k.canonical));
const kanterTilSkjulte = alleKanter.length - kantListe.length;
const collapsed = collapseSameAs({ persons: appPersons, unions, parentChild }, kantListe, new Map());
const kanon = (id: string) => collapsed.canonicalIdById[id] ?? id;
const komponenter = new Map<string, string[]>();
for (const p of appPersons) {
  const k = kanon(p.id);
  komponenter.set(k, [...(komponenter.get(k) ?? []), p.id]);
}

const udgaver: Udgave[] = kilder.map((k) => ({ sourceId: String(k.id), label: k.udgave, aar: k.aar }));
const udgaveLabel = new Map(udgaver.map((u) => [u.sourceId, u.label]));
const udgaveForPersonRaekke: Record<string, string> = {};
const koordAntal = new Map<string, number>();
for (const r of koord) {
  const pid = String(r.person_id);
  koordAntal.set(pid, (koordAntal.get(pid) ?? 0) + 1);
  udgaveForPersonRaekke[pid] = String(r.source_id);
}
const flereKoord = [...koordAntal.values()].filter((n) => n > 1).length;
const fritekstKilde: Record<string, string[]> = {};
for (const c of citater) (fritekstKilde[String(c.assertion_id)] ??= []).push(c.citat_tekst ?? '');

const raekkerPrKomp = new Map<string, PublicPersonFactRow[]>();
for (const r of faktaRaekker) {
  const k = kanon(String(r.person_id));
  raekkerPrKomp.set(k, [...(raekkerPrKomp.get(k) ?? []), r]);
}
const bioPrKomp = new Map<string, Record<string, unknown>[]>();
for (const r of bioRaekker) {
  const k = kanon(String(r.person_id));
  bioPrKomp.set(k, [...(bioPrKomp.get(k) ?? []), r]);
}
tid('foldning + gruppering', s);

// ---- 3. Visninger pr. komponent og udgave ----
s = performance.now();
type Vis = { valgt: string | null; vis: UdgaveFaktaVisning };
type Komp = { id: string; input: UdgaveFaktaInput; medFakta: string[]; visninger: Map<string | null, Vis>; form: string; chipLabels: string[] };
const komps: Komp[] = [];
const formAntal: Record<string, number> = { ingen: 0, chips: 0, skift: 0 };
for (const [id] of [...komponenter].sort((a, b) => Number(a[0]) - Number(b[0]))) {
  const input: UdgaveFaktaInput = { rows: raekkerPrKomp.get(id) ?? [], udgaver, udgaveForPersonRaekke, fritekstKilde };
  const medFakta = udgaverMedFakta(input);
  const versioner = mapPublicBioSourceVersionsV2(bioPrKomp.get(id) ?? []);
  const vaelger = byggUdgaveVaelger(versioner, udgaver, medFakta);
  formAntal[vaelger.form] += 1;
  // De udgaver læseren kan vælge: chipsenes udgaver (og udgaver med fakta); ingen → valgt = null.
  const valgbare = [...new Set([...vaelger.chips.map((c) => c.sourceId), ...medFakta])].filter((x) => udgaveLabel.has(x));
  const visninger = new Map<string | null, Vis>();
  if (!valgbare.length) visninger.set(null, { valgt: null, vis: byggUdgaveFakta(input, null) });
  for (const v of valgbare) visninger.set(v, { valgt: v, vis: byggUdgaveFakta(input, v) });
  komps.push({ id, input, medFakta, visninger, form: vaelger.form, chipLabels: vaelger.chips.map((c) => c.label) });
}
tid('byggUdgaveFakta + vælger', s);

// ---- 4. Tælling pr. valgt udgave og faktatype ----
type Taal = { linjer: number; enig: number; skriver: number; kunI: number; kunIVaerdier: number };
const taal = new Map<string, Map<string, Taal>>(); // valgt-label → type → tal
const tael = (valgt: string, t: string) => {
  const m = taal.get(valgt) ?? new Map<string, Taal>();
  taal.set(valgt, m);
  const x = m.get(t) ?? { linjer: 0, enig: 0, skriver: 0, kunI: 0, kunIVaerdier: 0 };
  m.set(t, x);
  return x;
};
let recordLabels = 0;
let legacyLabels = 0;
let labelsSkannet = 0;
const recordKomp = new Set<string>();
const skan = (komp: string, label: string) => {
  labelsSkannet++;
  if (label.includes('record-')) { recordLabels++; recordKomp.add(komp); }
  if (label.includes('legacy-source:')) { legacyLabels++; recordKomp.add(komp); }
};
for (const k of komps) {
  for (const l of k.chipLabels) skan(k.id, l);
  for (const { valgt, vis } of k.visninger.values()) {
    const vl = valgt == null ? '(ingen udgave)' : udgaveLabel.get(valgt)!;
    for (const l of vis.linjer) {
      const x = tael(vl, l.faktatype);
      x.linjer++;
      for (const n of l.noter) n.art === 'enig' ? x.enig++ : x.skriver++;
      for (const kk of l.kilder) skan(k.id, kk.label);
      for (const a of l.andre) skan(k.id, a.source.label);
    }
    for (const ki of vis.kunI) {
      const x = tael(vl, ki.faktatype);
      x.kunI++;
      x.kunIVaerdier += ki.vaerdier.length;
    }
  }
}

// ---- 5. Enig-par (til stikprøven) og tabstjek ----
type Side = { udgave: string; vaerdi: string; kilder: string[] };
type Par = { komp: string; faktatype: string; a: Side; b: Side; noegle: string };
const par = new Map<string, Par>();
const enigUdenModpart: string[] = [];
const tab: { komp: string; valgt: string; anden: string; faktatype: string; redaktoerAlene: boolean }[] = [];
let udenVaerdiLinjer = 0;
for (const k of komps) {
  for (const { valgt, vis } of k.visninger.values()) {
    if (valgt == null) continue;
    for (const l of vis.linjer) {
      for (const n of l.noter) {
        if (n.art !== 'enig') continue;
        const anden = k.visninger.get(n.udgave.sourceId)?.vis
          ?? byggUdgaveFakta(k.input, n.udgave.sourceId);
        const modparter = anden.linjer.filter((m) => m.faktatype === l.faktatype && faktaVaerdierEns(l.faktatype, l.vaerdi, m.vaerdi));
        if (!modparter.length) { enigUdenModpart.push(`${k.id}:${l.noegle}`); continue; }
        for (const m of modparter) {
          const [x, y] = [
            { noegle: l.noegle, side: { udgave: udgaveLabel.get(valgt)!, vaerdi: l.vaerdi, kilder: l.kilder.map((c) => c.label) } },
            { noegle: m.noegle, side: { udgave: n.udgave.label, vaerdi: m.vaerdi, kilder: m.kilder.map((c) => c.label) } },
          ].sort((p, q2) => (p.side.udgave < q2.side.udgave ? 1 : -1)); // nyeste udgave (»DAA 2018-20«) først
          const noegle = `${k.id}|${l.faktatype}|${x.noegle}|${y.noegle}`;
          if (!par.has(noegle)) par.set(noegle, { komp: k.id, faktatype: l.faktatype, a: x.side, b: y.side, noegle });
        }
      }
    }
    // Tabstjek: hver ikke-tom linje i en anden udgaves visning skal ses her som ✓, »skriver« eller »Kun i«.
    const egneFakta = new Set(vis.linjer.flatMap((l) => l.noegle.split(':')[1].split('+')));
    for (const [andenId, { vis: andenVis }] of k.visninger) {
      if (andenId == null || andenId === valgt || !k.medFakta.includes(andenId)) continue;
      for (const m of andenVis.linjer) {
        if (m.vaerdi === '') { udenVaerdiLinjer++; continue; }
        const faktaIds = m.noegle.split(':')[1].split('+');
        if (faktaIds.some((f) => egneFakta.has(f))) continue; // række uden entydig udgave: vises i begge
        const t = m.faktatype;
        const daekket = vis.linjer.some((l) => l.faktatype === t && l.noter.some((n) => n.udgave.sourceId === andenId
          && (n.art === 'enig' ? faktaVaerdierEns(t, l.vaerdi, m.vaerdi) : n.vaerdier.some((v) => v === m.vaerdi || faktaVaerdierEns(t, v, m.vaerdi)))))
          || vis.kunI.some((ki) => ki.udgave.sourceId === andenId && ki.faktatype === t
            && ki.vaerdier.some((v) => v === m.vaerdi || faktaVaerdierEns(t, v, m.vaerdi)));
        if (!daekket) {
          tab.push({ komp: k.id, valgt: udgaveLabel.get(valgt)!, anden: udgaveLabel.get(andenId)!, faktatype: t,
            redaktoerAlene: m.kilder.every((c) => c.kind === 'ingen') });
        }
      }
    }
  }
}

// ---- 6. Redaktørpåstandene (spec §5.1) ----
// Afgørelse: find faktummets linje i personrækkens egen udgave. Viser den en anden værdi end den valgte påstand →
// »bøgernes ord vist«. Viser den den valgte → »udgavens egen« eller »som i dag«; det skelnes med en probe gennem
// core: en syntetisk tredje udgave med samme faktum og samme værdi. Kun en udgaveegen linje får en note (»✓ også«)
// om den — en »som i dag«-linje indgår aldrig i noter (§5.2). Proben bruger kun core, ingen kopi af reglen.
type Klasse = 'udgavens egen' | 'bøgernes ord vist' | 'som i dag' | 'ingen linje';
const klasser: { assertion: number; person: number; faktatype: string; klasse: Klasse; udgave: string }[] = [];
const offentligeValgte = redaktoer.filter((r) => r.valgt && r.offentlig);
for (const r of offentligeValgte) {
  const pid = String(r.person_id);
  const k = komps.find((x) => x.id === kanon(pid))!;
  const raekke = k.input.rows.find((x) => String(x.assertion_id) === String(r.assertion_id) && x.chosen);
  if (!raekke) { klasser.push({ assertion: r.assertion_id, person: r.person_id, faktatype: r.faktatype, klasse: 'ingen linje', udgave: '-' }); continue; }
  const egen = udgaveForRaekker(k.input)[pid] ?? null;
  const vis = byggUdgaveFakta(k.input, egen);
  const linje = vis.linjer.find((l) => l.noegle.split(':')[1].split('+').includes(String(raekke.fact_id)));
  let klasse: Klasse;
  if (!linje) klasse = 'ingen linje';
  else if (linje.vaerdi !== factValue(raekke)) klasse = 'bøgernes ord vist';
  else if (egen == null) klasse = 'som i dag';
  else {
    const probe: Udgave = { sourceId: '__probe', label: '\u0000probe', aar: 1 };
    const pin: UdgaveFaktaInput = {
      ...k.input,
      udgaver: [...k.input.udgaver, probe],
      udgaveForPersonRaekke: { ...k.input.udgaveForPersonRaekke, __probeperson: '__probe' },
      rows: [...k.input.rows, { ...raekke, person_id: '__probeperson', fact_id: '__probefact', assertion_id: '__probeassertion',
        chosen: true, source_id: '__probe', source_label: 'probe', record_ref: null, record_label: null, citation_label: null }],
    };
    const pv = byggUdgaveFakta(pin, egen);
    const pl = pv.linjer.find((l) => l.noegle === linje.noegle);
    klasse = pl?.noter.some((n) => n.udgave.sourceId === '__probe' && n.art === 'enig') ? 'udgavens egen' : 'som i dag';
  }
  klasser.push({ assertion: r.assertion_id, person: r.person_id, faktatype: r.faktatype, klasse, udgave: egen == null ? '-' : udgaveLabel.get(egen)! });
}

// ---- 7. Conrad-tjek (komponent med 255, 392, 1198) ----
const conradKomp = komps.find((x) => x.id === kanon('255'))!;
const conradSamlet = ['255', '392', '1198'].every((p) => kanon(p) === conradKomp.id);
const conrad2018 = conradKomp.visninger.get('1')?.vis;
const conradLinjer = (t: string) => (conrad2018?.linjer ?? []).filter((l) => l.faktatype === t);
const noteArt = (t: string) => conradLinjer(t).map((l) => l.noter.map((n) => `${n.art}@${n.udgave.label}`).join('+') || '(ingen note)');
// 392's navnefaktum: linjen skal vise 392's bundne påstand (bogens ord), ikke redaktørens valg (spec §5.2).
const conradNavnRaekker = conradKomp.input.rows.filter((r) => String(r.person_id) === '392' && r.faktatype === 'navn');
const conradBundet = conradNavnRaekker.find((r) => r.record_ref);
const conradValgt = conradNavnRaekker.find((r) => r.chosen);
const conradNavn = conradLinjer('navn').find((l) => conradBundet && l.noegle.split(':')[1].split('+').includes(String(conradBundet.fact_id)));
const conradBundetVist = !!(conradNavn && conradBundet && conradNavn.vaerdi === factValue(conradBundet));
const conradValgtErRedaktoer = conradValgt?.source_id == null;

// ---- 8. Stikprøve: 40 enig-par, fast seed »6e1« ----
const fnv = (str: string) => { let h = 0x811c9dc5; for (const c of str) { h ^= c.codePointAt(0)!; h = Math.imul(h, 0x01000193); } return h >>> 0; };
const mulberry32 = (a: number) => () => {
  a |= 0; a = (a + 0x6d2b79f5) | 0;
  let t = Math.imul(a ^ (a >>> 15), 1 | a);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const alleParr = [...par.values()].sort((a, b) => (a.noegle < b.noegle ? -1 : a.noegle > b.noegle ? 1 : 0));
const rnd = mulberry32(fnv('6e1'));
const blandet = [...alleParr];
for (let i = blandet.length - 1; i > 0; i--) {
  const j = Math.floor(rnd() * (i + 1));
  [blandet[i], blandet[j]] = [blandet[j], blandet[i]];
}
// 40 tilfældige par; derefter tillæg i samme blandede rækkefølge, til hver type med ✓-par har mindst 3 (alle, hvis færre).
const stik: (Par & { tillaeg: boolean })[] = blandet.slice(0, 40).map((p) => ({ ...p, tillaeg: false }));
for (const t of [...new Set(alleParr.map((p) => p.faktatype))].sort()) {
  const mål = Math.min(3, alleParr.filter((p) => p.faktatype === t).length);
  for (const p of blandet.slice(40)) {
    if (stik.filter((x) => x.faktatype === t).length >= mål) break;
    if (p.faktatype === t) stik.push({ ...p, tillaeg: true });
  }
}
const antalTillaeg = stik.filter((p) => p.tillaeg).length;
const esc = (x: string) => x.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const side = (x: Side) => `<b>${esc(x.vaerdi)}</b><br><small>${esc(x.udgave)} · ${esc(x.kilder.join('; '))}</small>`;
const html = `<!doctype html>
<html lang="da"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stikprøve 6e-1</title>
<style>body{font-family:system-ui,sans-serif;max-width:60rem;margin:1rem auto;padding:0 1rem;line-height:1.4}
table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:.35rem .5rem;vertical-align:top;text-align:left}
th{background:#f3f3f3}small{color:#555}</style></head><body>
<h1>Stikprøve: »✓ også i …«</h1>
<p>Læserfladen viser fakta fra én udgave ad gangen. Når den anden udgave siger det samme, står der
<b>»✓ også i DAA 1939«</b> (eller »✓ også i DAA 2018-20«) ved oplysningen. Et ✓ betyder altså: <i>de to bøger siger det
samme</i>. Står der et ✓, hvor bøgerne i virkeligheden siger noget forskelligt, er det et falsk ✓.</p>
<p>Herunder er ${stik.length} par (af ${alleParr.length}), hvor læserfladen sætter ✓: 40 tilfældige og ${antalTillaeg} tillæg (markeret »tillæg«), så hver faktatype har mindst 3 par. Hver række viser begge
bøgers ord med udgave og side. <b>Markér de numre, der er falske</b> — ét falsk par slår ✓ fra for den faktatype,
indtil reglen er rettet.</p>
<table><thead><tr><th>Nr</th><th>Person (id)</th><th>Faktatype</th><th>Udgave 1</th><th>Udgave 2</th></tr></thead><tbody>
${stik.map((p, i) => `<tr><td>${i + 1}</td><td>${esc(p.komp)}</td><td>${esc(p.faktatype)}${p.tillaeg ? '<br><small>tillæg</small>' : ''}</td><td>${side(p.a)}</td><td>${side(p.b)}</td></tr>`).join('\n')}
</tbody></table>
<p><small>Seed »6e1«; stand-in ${esc(process.env.PGDATABASE ?? '')}.</small></p>
</body></html>
`;
writeFileSync(arkAbs, html, 'utf8');

// ---- 9. Stdout: kun tal og id'er ----
const ln = (...x: unknown[]) => console.log(...x);
ln(`# 6e-1 måling — stand-in ${process.env.PGDATABASE}`);
ln(`offentlige personrækker (anon-regel): ${personer.length}; afklarede samme_som-kanter: ${alleKanter.length}, anon ser ${kantListe.length} (${kanterTilSkjulte} rører en skjult række og foldes ikke); karantæne: ${collapsed.quarantined.length}`);
const aarsager = new Map<string, number>();
for (const qn of collapsed.quarantined) aarsager.set(qn.reason.replace(/\(.*\)/, '(…)'), (aarsager.get(qn.reason.replace(/\(.*\)/, '(…)')) ?? 0) + 1);
ln(`karantæne-årsager: ${[...aarsager].map(([a, n]) => `${a} ${n}`).join(' · ') || '-'}`);
ln(`komponenter (kanoniske personer): ${komps.length}; med >1 medlem: ${[...komponenter.values()].filter((m) => m.length > 1).length}; personer med >1 koordinatrække: ${flereKoord}`);
ln(`fakta-rækker fra RPC: ${faktaRaekker.length}; bio-rækker: ${bioRaekker.length}; fritekstcitater: ${citater.length}`);
ln('\n## Pr. valgt udgave og faktatype (linjer / linjer m. ✓-note / »skriver«-noter / kunI-grupper (værdier))');
for (const [vl, m] of [...taal].sort()) {
  ln(`### valgt ${vl}`);
  const sum: Taal = { linjer: 0, enig: 0, skriver: 0, kunI: 0, kunIVaerdier: 0 };
  for (const [t, x] of [...m].sort((a, b) => b[1].linjer - a[1].linjer)) {
    ln(`${t.padEnd(14)} linjer ${String(x.linjer).padStart(5)}  enig ${String(x.enig).padStart(4)}  skriver ${String(x.skriver).padStart(4)}  kunI ${String(x.kunI).padStart(4)} (${x.kunIVaerdier})`);
    for (const key of Object.keys(sum) as (keyof Taal)[]) sum[key] += x[key];
  }
  ln(`${'I ALT'.padEnd(14)} linjer ${String(sum.linjer).padStart(5)}  enig ${String(sum.enig).padStart(4)}  skriver ${String(sum.skriver).padStart(4)}  kunI ${String(sum.kunI).padStart(4)} (${sum.kunIVaerdier})`);
}
ln(`\n## Vælgerform pr. komponent: ingen ${formAntal.ingen} · chips ${formAntal.chips} · skift ${formAntal.skift}`);
ln(`komponenter med fakta i 2+ udgaver: ${komps.filter((k) => k.medFakta.length > 1).length}`);
ln(`\n## Etiketter: skannet ${labelsSkannet}; »record-« ${recordLabels}; »legacy-source:« ${legacyLabels}${recordKomp.size ? ` (komponenter: ${[...recordKomp].join(', ')})` : ''}`);
ln(`\n## Redaktørpåstande (citation uden source_id, ekskl. forældrefamilie/forældre_ukendt): ${redaktoer.length} i alt`);
ln(`valgt + offentlig: ${offentligeValgte.length}; ikke valgt + offentlig: ${redaktoer.filter((r) => !r.valgt && r.offentlig).length} (${redaktoer.filter((r) => !r.valgt && r.offentlig).map((r) => `${r.faktatype}@${r.person_id}`).join(', ')}); på ikke-offentlige rækker: ${redaktoer.filter((r) => !r.offentlig).length} (${[...new Set(redaktoer.filter((r) => !r.offentlig).map((r) => r.faktatype))].join(', ')})`);
for (const kl of ['udgavens egen', 'bøgernes ord vist', 'som i dag', 'ingen linje'] as Klasse[]) {
  const xs = klasser.filter((x) => x.klasse === kl);
  ln(`${kl.padEnd(18)} ${xs.length}  ${xs.map((x) => `${x.faktatype}@${x.person}(${x.udgave})`).join(', ')}`);
}
ln('\n## Conrad (255, 392, 1198)');
ln(`samme komponent: ${conradSamlet ? 'ja' : 'NEJ'} (kanonisk ${conradKomp.id}); udgaver med fakta: ${conradKomp.medFakta.map((x) => udgaveLabel.get(x)).join(', ')}`);
ln(`2018-20 navn-linjer: ${conradLinjer('navn').length}; 392's bundne navnepåstand vist (ikke redaktørens valg; valgt er redaktørens: ${conradValgtErRedaktoer ? 'ja' : 'nej'}): ${conradBundetVist ? 'ja' : 'NEJ'}; noter: ${conradNavn ? conradNavn.noter.map((n) => `${n.art}@${n.udgave.label}`).join('+') : '-'}`);
for (const t of ['navn', 'fødsel', 'død', 'titel', 'adling', 'begravelse']) ln(`2018-20 ${t}: ${noteArt(t).join(' | ') || '(ingen linje)'}`);
ln(`kunI i 2018-20-visningen: ${(conrad2018?.kunI ?? []).map((x) => `${x.faktatype}(${x.vaerdier.length})`).join(', ') || '(ingen)'}`);
ln(`\n## Tabstjek: linjer i en anden udgave uden ✓/skriver/kunI: ${tab.length} (redaktør alene: ${tab.filter((x) => x.redaktoerAlene).length}; øvrige: ${tab.filter((x) => !x.redaktoerAlene).length})`);
for (const x of tab) ln(`  komp ${x.komp} ${x.faktatype} (valgt ${x.valgt}, mangler fra ${x.anden})${x.redaktoerAlene ? ' [redaktør alene]' : ''}`);
ln(`linjer uden vist værdi (omstridt/tomt valg) i andre udgaver, ikke tjekket: ${udenVaerdiLinjer}`);
ln(`selvkonsistens (IKKE bevis for at intet ✓ er falsk — kun projektejerens dom over arket er): ✓-noter uden ens linje i den anden udgaves visning: ${enigUdenModpart.length}${enigUdenModpart.length ? ` (${enigUdenModpart.join(', ')})` : ''}`);
const stikType = new Map<string, number>();
for (const p of stik) stikType.set(p.faktatype, (stikType.get(p.faktatype) ?? 0) + 1);
const parType = new Map<string, number>();
for (const p of alleParr) parType.set(p.faktatype, (parType.get(p.faktatype) ?? 0) + 1);
ln(`\n## Stikprøve: ${stik.length} af ${alleParr.length} unikke ✓-par (seed »6e1«; 40 tilfældige + ${antalTillaeg} tillæg) → ${arkAbs}`);
ln(`par pr. type: ${[...parType].map(([t, n]) => `${t} ${n}`).join(' · ')}`);
ln(`i stikprøven: ${[...stikType].map(([t, n]) => `${t} ${n}`).join(' · ')}; heraf tillæg: ${[...new Set(stik.filter((p) => p.tillaeg).map((p) => p.faktatype))].map((t) => `${t} ${stik.filter((p) => p.tillaeg && p.faktatype === t).length}`).join(' · ') || '-'}`);
ln(`\n## Tider (ms): ${tider.map(([n, ms]) => `${n} ${ms}`).join(' · ')} · i alt ${Math.round(performance.now() - t0)}`);

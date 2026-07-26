// Hvor mange 1939-personer får NUL kandidater ("formodet ny"), og hvor mange af dem
// har i virkeligheden en oplagt modpart i 2018-20? Kører den rigtige matcher.
import { readFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { matchUdgaver, udledKilderForAegtefaeller } from '../../packages/core/src/matchUdgaver';
import { matchKey } from '../../packages/core/src/navnevarianter';
import type { MatchFrame } from '../../packages/core/src/matchUdgaver';

const raw = JSON.parse(readFileSync('tmp/collapse-input.json', 'utf8'));
const { unions } = buildFamilyGraph(raw.members);
const kilde = new Map<string, number>();
for (const k of raw.kilde) kilde.set(k.person_id, k.source_id);

const medKilde = udledKilderForAegtefaeller(
  raw.persons.map((p: any) => ({ id: p.id as string, sourceIds: kilde.has(p.id) ? [kilde.get(p.id)!] : [] })),
  unions,
);
const kildeAf = new Map(medKilde.map((p) => [p.id, p.sourceIds]));
const pById = new Map<string, any>(raw.persons.map((p: any) => [p.id, p]));

const frame = (p: any): MatchFrame => ({
  id: p.id,
  nameKey: matchKey(p.name ?? ''),
  birthMin: p.born ?? null, birthMax: p.born ?? null,
  deathMin: p.died ?? null, deathMax: p.died ?? null,
  sex: p.koen === 'mand' || p.koen === 'kvinde' ? p.koen : 'ukendt',
});

const NY = 3; // 1939 er "ny udgave"
const A: MatchFrame[] = [], B: MatchFrame[] = [];
for (const p of raw.persons) {
  ((kildeAf.get(p.id) ?? []).includes(NY) ? A : B).push(frame(p));
}
const pairs = matchUdgaver(A, B);
// UI'et kasserer tier==='none' (sammenlign.ts:27) — det er DET filter brugeren mærker
const synlige = pairs.filter((x) => x.tier !== 'none');
const medKandidat = new Set(synlige.map((x) => String(x.aId)));
const medNogetSomHelst = new Set(pairs.map((x) => String(x.aId)));
const uden = A.filter((f) => !medKandidat.has(String(f.id)));

console.log(`A-side (1939): ${A.length}   B-side: ${B.length}`);
console.log(`får mindst én kandidat: ${A.length - uden.length}`);
console.log(`NUL SYNLIGE kandidater ("formodet ny"): ${uden.length}`);
const harSkjulte = uden.filter((f) => medNogetSomHelst.has(String(f.id)));
console.log(`  heraf har en kandidat der ER fundet, men kasseret som tier='none': ${harSkjulte.length}`);
const tierFordeling = new Map<string, number>();
for (const x of pairs) tierFordeling.set(String(x.tier), (tierFordeling.get(String(x.tier)) ?? 0) + 1);
console.log(`  par-fordeling: ${[...tierFordeling].map(([k, v]) => `${k}=${v}`).join('  ')}`);

// Har de i virkeligheden en oplagt modpart? Test: identisk foldet navnenøgle i B.
const bByKey = new Map<string, MatchFrame[]>();
for (const f of B) {
  if (!f.nameKey) continue;
  const arr = bByKey.get(f.nameKey); if (arr) arr.push(f); else bByKey.set(f.nameKey, [f]);
}
const tomtNavn = uden.filter((f) => !f.nameKey).length;
const eksaktModpart = uden.filter((f) => f.nameKey && bByKey.has(f.nameKey));
const bedsteSkjulte = new Map<string, number>();
for (const x of pairs) {
  const k = String(x.aId), sc = x.score ?? 0;
  if (!bedsteSkjulte.has(k) || sc > bedsteSkjulte.get(k)!) bedsteSkjulte.set(k, sc);
}
const taet = uden.filter((f) => (bedsteSkjulte.get(String(f.id)) ?? 0) >= 0.6);
console.log(`  heraf med en kasseret kandidat på score >= 0,60 (tærsklen er 0,70): ${taet.length}`);
console.log(`  heraf uden brugbart navn (NN/tomt): ${tomtNavn}`);
console.log(`  heraf med EKSAKT samme navnenøgle i 2018-20: ${eksaktModpart.length}  <-- burde kunne matches`);

console.log('\nEksempler på "formodet nye" med eksakt navne-modpart:');
for (const f of eksaktModpart.slice(0, 12)) {
  const a = pById.get(String(f.id));
  const b = bByKey.get(f.nameKey)!.map((x) => pById.get(String(x.id)));
  const aar = (p: any) => [p.born, p.died].filter(Boolean).join('–') || 'ingen årstal';
  console.log(`  ${a.name} (${aar(a)})  ↔  ${b.map((x) => `${x.name} (${aar(x)})`).join(' / ')}`);
}

// --- Hvorfor falder de igennem? Scoren er
//     0,6·navn + 0,2·fødsel-overlap + 0,1·død-overlap + 0,1·køn
// og overlapEvidence kræver at BEGGE sider har en dato. En ægtefælle uden årstal
// kan derfor højst nå 0,6 + 0,1 = 0,70 — og kun hvis navnet er identisk OG køn
// er kendt på begge sider. Tærsklen er 0,70.
let udenDatoIAlt = 0, udenDatoOgKasseret = 0;
for (const f of uden) {
  const p = pById.get(String(f.id));
  const harDato = p.born != null || p.died != null;
  if (!harDato) { udenDatoIAlt++; if (medNogetSomHelst.has(String(f.id))) udenDatoOgKasseret++; }
}
console.log(`\n  "formodet nye" HELT uden årstal: ${udenDatoIAlt} af ${uden.length}`);

// Hvad ville en evidens-normaliseret score gøre? Vægt kun det der KAN vurderes.
const cfg = { wName: 0.6, wBirth: 0.2, wDeath: 0.1, wSex: 0.1, review: 0.7, auto: 0.9 };
let nyReview = 0, nyAuto = 0;
const bedstNorm = new Map<string, number>();
for (const x of pairs) {
  const a = pById.get(String(x.aId)), b = pById.get(String(x.bId));
  const kanFoedsel = (a.born != null) && (b.born != null);
  const kanDoed = (a.died != null) && (b.died != null);
  const kanKoen = a.koen != null && b.koen != null;
  const vaegt = cfg.wName + (kanFoedsel ? cfg.wBirth : 0) + (kanDoed ? cfg.wDeath : 0) + (kanKoen ? cfg.wSex : 0);
  const raa = cfg.wName * x.nameSim
    + (kanFoedsel && x.birthOverlap ? cfg.wBirth : 0)
    + (kanDoed && x.deathOverlap ? cfg.wDeath : 0)
    + (kanKoen && x.sexEq ? cfg.wSex : 0);
  const norm = raa / vaegt;
  const k = String(x.aId);
  if (!bedstNorm.has(k) || norm > bedstNorm.get(k)!) bedstNorm.set(k, norm);
}
for (const f of uden) {
  const s = bedstNorm.get(String(f.id)) ?? 0;
  if (s >= cfg.auto) nyAuto++; else if (s >= cfg.review) nyReview++;
}
console.log(`  med evidens-normaliseret score ville af de ${uden.length}:`);
console.log(`    ${nyAuto} blive "stærk kandidat" og ${nyReview} "til gennemsyn"`);
console.log(`    ${uden.length - nyAuto - nyReview} stadig være formodet nye`);

// Hvor tung bliver listen? (UI'et viser højst 5 forslag pr. person)
const antalPr = uden.map((f) => pairs.filter((x) => String(x.aId) === String(f.id)).length).sort((a, b) => a - b);
const median = antalPr[Math.floor(antalPr.length / 2)];
const vist = uden.reduce((s, f) => s + Math.min(5, pairs.filter((x) => String(x.aId) === String(f.id)).length), 0);
console.log(`\n  forslag pr. person: median ${median}, størst ${antalPr[antalPr.length - 1]}`);
console.log(`  rækker der vises i alt (cap 5 pr. person): ${vist}`);

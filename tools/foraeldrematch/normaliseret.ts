// Måler evidensNormaliseret mod prod-data med den RIGTIGE matcher og assignTiers —
// ikke en formel gengivet i et script. Sammenligner tier-fordeling og de risikable
// tilfælde (navne-match uden nogen dato på nogen af siderne).
import { readFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { matchUdgaver, udledKilderForAegtefaeller, defaultCfg } from '../../packages/core/src/matchUdgaver';
import { matchKey } from '../../packages/core/src/navnevarianter';
import type { MatchFrame, ScoredPair } from '../../packages/core/src/matchUdgaver';

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
  id: p.id, nameKey: matchKey(p.name ?? ''),
  birthMin: p.born ?? null, birthMax: p.born ?? null,
  deathMin: p.died ?? null, deathMax: p.died ?? null,
  sex: p.koen === 'mand' || p.koen === 'kvinde' ? p.koen : 'ukendt',
});
const A: MatchFrame[] = [], B: MatchFrame[] = [];
for (const p of raw.persons) (((kildeAf.get(p.id) ?? []).includes(3)) ? A : B).push(frame(p));

const koer = (norm: boolean) => matchUdgaver(A, B, { ...defaultCfg(), evidensNormaliseret: norm });
const foer = koer(false), efter = koer(true);

const tael = (ps: ScoredPair[]) => {
  const t = { auto: 0, review: 0, none: 0 };
  for (const p of ps) t[p.tier ?? 'none']++;
  return t;
};
const personerMedSynlig = (ps: ScoredPair[]) =>
  new Set(ps.filter((p) => p.tier !== 'none').map((p) => String(p.aId))).size;

console.log(`A=${A.length}  B=${B.length}\n`);
console.log(['', 'auto', 'review', 'none', 'personer m. forslag'].map((s, i) => i === 0 ? s.padEnd(10) : s.padStart(i === 4 ? 22 : 9)).join(''));
for (const [navn, ps] of [['før', foer], ['efter', efter]] as const) {
  const t = tael(ps);
  console.log([navn.padEnd(10), String(t.auto).padStart(9), String(t.review).padStart(9),
    String(t.none).padStart(9), String(personerMedSynlig(ps)).padStart(22)].join(''));
}

// Risiko: hvor mange nye synlige par hviler UDELUKKENDE på navnet?
const synligEfter = efter.filter((p) => p.tier !== 'none');
const synligFoerKeys = new Set(foer.filter((p) => p.tier !== 'none').map((p) => `${p.aId}|${p.bId}`));
const nye = synligEfter.filter((p) => !synligFoerKeys.has(`${p.aId}|${p.bId}`));
const kunNavn = nye.filter((p) => !p.birthKendt && !p.deathKendt);
const kunNavnAuto = kunNavn.filter((p) => p.tier === 'auto');
console.log(`\nnye synlige par: ${nye.length}`);
console.log(`  heraf uden ét eneste årstal på nogen af siderne: ${kunNavn.length}`);
console.log(`  heraf markeret "stærk": ${kunNavnAuto.length}  <-- risikoen`);

// Modsat: mister vi noget? Par der var synlige før og forsvinder nu.
const synligEfterKeys = new Set(synligEfter.map((p) => `${p.aId}|${p.bId}`));
const tabt = foer.filter((p) => p.tier !== 'none' && !synligEfterKeys.has(`${p.aId}|${p.bId}`));
console.log(`\npar der var synlige før og IKKE er det nu: ${tabt.length}`);
for (const p of tabt.slice(0, 5)) {
  const a = pById.get(String(p.aId)), b = pById.get(String(p.bId));
  console.log(`  ${a.name} ↔ ${b.name}  (navn ${p.nameSim.toFixed(2)})`);
}

console.log('\nEksempler på nye "stærke" uden årstal:');
for (const p of kunNavnAuto.slice(0, 8)) {
  const a = pById.get(String(p.aId)), b = pById.get(String(p.bId));
  console.log(`  ${a.name} ↔ ${b.name}  (navn ${p.nameSim.toFixed(2)}, køn ${p.sexEq ? '✓' : '✗'})`);
}

// Mister de 5 tabte par deres person et forslag, eller har personen et andet?
const aMedSynligEfter = new Set(synligEfter.map((p) => String(p.aId)));
const tabteUdenErstatning = tabt.filter((p) => !aMedSynligEfter.has(String(p.aId)));
console.log(`\ntabte par hvis person står HELT uden forslag bagefter: ${tabteUdenErstatning.length}`);
for (const p of tabteUdenErstatning) {
  const a = pById.get(String(p.aId)), b = pById.get(String(p.bId));
  console.log(`  ${a.name} ↔ ${b.name}`);
}

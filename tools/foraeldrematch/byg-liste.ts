// Bygger en arbejdsliste over de forældrepar der skal matches for at frigive
// de karantænerede samme_som-grupper. Sorteret så de par der frigiver flest
// børn ligger øverst. Read-only; skriver til work/ (gitignoreret, kan rumme PII).
import { readFileSync, writeFileSync } from 'node:fs';
import { buildFamilyGraph } from '../../packages/core/src/buildFamilyGraph';
import { collapseSameAs } from '../../packages/core/src/collapseSameAs';
import type { AppPerson, Db, SameAsEdge } from '../../packages/core/src/types';

const raw = JSON.parse(readFileSync('tmp/collapse-input.json', 'utf8'));
type P = {
  id: string; name: string; born: number | null; died: number | null;
  koen: string | null; levende: boolean; vis_foedt: string; vis_doed: string; vis_titel: string;
};
const pById = new Map<string, P>(raw.persons.map((p: P) => [p.id, p]));

const persons: AppPerson[] = raw.persons.map((p: P) => ({
  id: p.id, name: p.name ?? '', born: p.born ?? null, died: p.died ?? null,
  years: '', title: '', bio: '', privat: false, koen: (p.koen as any) ?? null,
}));
const { unions, parentChild } = buildFamilyGraph(raw.members);
const db: Db = { persons, unions, parentChild };
const edges: SameAsEdge[] = raw.sammesom.map((r: any) => ({ alias: r.fra, canonical: r.til }));
const res = collapseSameAs(db, edges, new Map());

const kilde = new Map<string, { source_id: number; linje: string; nr: number | null }>();
for (const k of raw.kilde) kilde.set(k.person_id, k);
const src = (id: string) => kilde.get(id)?.source_id;
const ref = (id: string) => {
  const k = kilde.get(id);
  if (!k) return '(ægtefælle)';
  return k.source_id === 3 ? `1939 nr ${k.nr}` : `2018-20 ${k.linje}-${k.nr}`;
};
const foraeldreAf = (id: string) => [...new Set(parentChild.filter((pc) => pc.child === id).map((pc) => pc.parent))];

// Grupper karantænerne på (1939-forældresæt, 2018-20-forældresæt)
type Klump = { f39: string[]; f20: string[]; boern: Array<[string, string]> };
const klumper = new Map<string, Klump>();
for (const q of res.quarantined) {
  const a = q.members.find((m) => src(m) === 3);
  const b = q.members.find((m) => src(m) === 1);
  if (!a || !b) continue;
  const f39 = foraeldreAf(a).sort(), f20 = foraeldreAf(b).sort();
  if (!f39.length || !f20.length) continue;
  const key = `${f39.join(',')}|${f20.join(',')}`;
  const k = klumper.get(key) ?? { f39, f20, boern: [] };
  k.boern.push([a, b]);
  klumper.set(key, k);
}

const sorteret = [...klumper.values()].sort((x, y) => y.boern.length - x.boern.length);

// Levende personer holdes helt ude af listen (invariant 8)
const harLevende = (k: Klump) => [...k.f39, ...k.f20, ...k.boern.flat()].some((id) => pById.get(id)?.levende);
const udeladt = sorteret.filter(harLevende);
const liste = sorteret.filter((k) => !harLevende(k));

const vis = (id: string) => {
  const p = pById.get(id)!;
  const t = p.vis_titel ? `${p.vis_titel} ` : '';
  const d = [p.vis_foedt, p.vis_doed].filter(Boolean).join(' ');
  return `${t}${p.name}${d ? ` (${d})` : ''} — ${ref(id)}`;
};
// Forslag til person-til-person-parring inden for forældreparret: navne-lighed
// (stavevarianter på tværs af udgaverne) + køn når det kendes. KUN et forslag —
// redaktøren bekræfter.
const normNavn = (n: string) => n.toLowerCase()
  .replace(/\b(von|van|til|zu|de|af)\b/g, ' ')
  .replace(/[æä]/g, 'e').replace(/[øö]/g, 'o').replace(/[åa]/g, 'a')
  .replace(/[^a-z ]/g, ' ').replace(/\s+/g, ' ').trim();
const lev = (a: string, b: string) => {
  const m = a.length, n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++)
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[n];
};
const lighed = (a: string, b: string) => {
  const x = normNavn(a), y = normNavn(b);
  if (!x || !y) return 0;
  return 1 - lev(x, y) / Math.max(x.length, y.length);
};
const aarTjek = (a: P, b: P) => {
  const ya = [a.born, a.died].filter(Boolean), yb = [b.born, b.died].filter(Boolean);
  if (!ya.length || !yb.length) return '–';
  const fælles = ya.filter((y) => yb.includes(y!));
  if (fælles.length && fælles.length === Math.min(ya.length, yb.length)) return '✅';
  if (fælles.length) return '🟡';
  return '⚠️';
};
// Grådig parring: bedste navnelighed først, køn må ikke modsige
const parring = (k: Klump) => {
  const kand: Array<{ a: string; b: string; s: number }> = [];
  for (const a of k.f39) for (const b of k.f20) {
    const pa = pById.get(a)!, pb = pById.get(b)!;
    if (pa.koen && pb.koen && pa.koen !== pb.koen) continue;
    kand.push({ a, b, s: lighed(pa.name, pb.name) });
  }
  kand.sort((x, y) => y.s - x.s);
  const brugtA = new Set<string>(), brugtB = new Set<string>();
  const ud: Array<{ a: string; b: string; s: number }> = [];
  for (const c of kand) {
    if (brugtA.has(c.a) || brugtB.has(c.b)) continue;
    brugtA.add(c.a); brugtB.add(c.b); ud.push(c);
  }
  return {
    par: ud,
    uparrede: [...k.f39.filter((x) => !brugtA.has(x)), ...k.f20.filter((x) => !brugtB.has(x))],
  };
};
let ud = `# Arbejdsliste: forældre der skal matches

Genereret ${new Date().toISOString().slice(0, 10)} · **gitignoreret** (kan rumme PII)

Hvert punkt er ét forældrepar der optræder i begge udgaver uden at være matchet.
Matcher du personerne i punktet, forsvinder karantænen for **alle** de børn der er
nævnt — de vises derefter som én person i stedet for to.

> ℹ️ **Kræver at rettelsen er deployet.**
> Ægtefæller har sjældent eget bog-nummer, og matcheren gav kun personer med et
> bog-nummer et udgave-tilhør — derfor kunne ingen af punkterne gennemføres.
> \`udledKilderForAegtefaeller\` (PR #90) lader ægtefællen arve udgaven fra sin
> partner, entydigt eller slet ikke. Målt mod prod-data: 627 ægtefæller får en
> udgave, 0 bliver flertydige, og **alle 77 forældrepar kan derefter gennemføres**.
>
> Indtil web-appen er deployet med rettelsen, er listen en oversigt — ikke en to-do.

Arbejd oppefra: de øverste giver mest for indsatsen.

## Signaturforklaring

| Tegn | Betyder |
|---|---|
| ☐ | Forslag med god navnelighed — sandsynligvis oplagt |
| ☐❓ | Navnene ligner ikke hinanden nok til at jeg tør foreslå det. Tjek selv |
| ✅ | **Årstallene** stemmer (kun år — dag og måned kan stadig afvige mellem udgaverne) |
| 🟡 | Årstallene overlapper delvist |
| ⚠️ | Årstallene stemmer ikke. Undersøg før du matcher |
| – | Den ene side mangler årstal |

Parringen inden for hvert punkt er **mit forslag**, ikke en afgørelse: navnelighed
plus køn hvor det er kendt. Du bekræfter i redaktør-fladen.

Ægtefæller står uden nummer — markeret \`(ægtefælle)\` — fordi de ikke har en egen post i bogen
— de er kun nævnt i deres mands eller kones opslag.

`;
let løbende = 0;
liste.forEach((k, i) => {
  løbende += k.boern.length;
  const { par, uparrede } = parring(k);
  ud += `\n## ${i + 1}. Frigiver ${k.boern.length} ${k.boern.length === 1 ? 'barn' : 'børn'} (akkumuleret ${løbende})\n\n`;
  ud += `| ✓ | 1939 | 2018-20 | Årstal |\n|---|---|---|---|\n`;
  for (const c of par) {
    const pa = pById.get(c.a)!, pb = pById.get(c.b)!;
    ud += `| ${c.s > 0.75 ? '☐' : '☐❓'} | ${vis(c.a)} | ${vis(c.b)} | ${aarTjek(pa, pb)} |\n`;
  }
  for (const u of uparrede) ud += `| ☐❓ | ${src(u) === 3 ? vis(u) : ''} | ${src(u) === 3 ? '' : vis(u)} | – |\n`;
  ud += `\nBørn der frigives: ${k.boern.map(([a]) => `${pById.get(a)!.name} (${ref(a)})`).join(' · ')}\n`;
});

ud += `\n---\n\n**I alt ${liste.length} forældrepar → ${løbende} børn frigives.**\n`;
if (udeladt.length) {
  const n = udeladt.reduce((s, k) => s + k.boern.length, 0);
  ud += `\n${udeladt.length} par (${n} børn) er udeladt af listen, fordi de omfatter en nulevende person (invariant 8). De skal håndteres direkte i redaktør-fladen.\n`;
}
writeFileSync('work/arbejdsliste-foraeldrematch.md', ud);
console.log(`skrev work/arbejdsliste-foraeldrematch.md`);
console.log(`  forældrepar på listen: ${liste.length}`);
console.log(`  børn der frigives:     ${løbende}`);
console.log(`  udeladt (levende):     ${udeladt.length} par`);
console.log(`  top 5: ${liste.slice(0, 5).map((k) => k.boern.length).join(', ')} børn`);
let sikre = 0, tjek = 0, uparret = 0;
for (const k of liste) {
  const { par, uparrede } = parring(k);
  uparret += uparrede.length;
  for (const c of par) {
    const a = aarTjek(pById.get(c.a)!, pById.get(c.b)!);
    if (c.s > 0.75 && (a === '✅' || a === '–')) sikre++; else tjek++;
  }
}
console.log(`  person-forslag i alt:  ${sikre + tjek} (${sikre} oplagte, ${tjek} kræver et kig)`);
console.log(`  uden modpart-forslag:  ${uparret}`);

// Hvor mange af de forældre der skal matches, har overhovedet et bog-nummer?
const skalMatches = new Set<string>();
for (const k of liste) for (const id of [...k.f39, ...k.f20]) if (!alleErMatchet(id)) skalMatches.add(id);
function alleErMatchet(id: string) { return Object.prototype.hasOwnProperty.call(res.canonicalIdById, id); }
let medNr = 0, udenNr = 0;
for (const id of skalMatches) (kilde.has(id) ? medNr++ : udenNr++);
console.log(`\n  forældre der mangler match: ${skalMatches.size}`);
console.log(`    heraf med bog-nummer:     ${medNr}`);
console.log(`    heraf kun ægtefælle-nævnt: ${udenNr}`);

// Kan hvert forældrepar overhovedet løses i den nuværende flade?
let heltLoesbare = 0, delvis = 0, uloeselige = 0, boernLoesbare = 0, boernBlokerede = 0;
for (const k of liste) {
  const alle = [...k.f39, ...k.f20];
  const manglerMatch = alle.filter((id) => !Object.prototype.hasOwnProperty.call(res.canonicalIdById, id));
  const kanMatches = manglerMatch.filter((id) => kilde.has(id));
  if (manglerMatch.length === 0) continue;
  if (kanMatches.length === manglerMatch.length) { heltLoesbare++; boernLoesbare += k.boern.length; }
  else if (kanMatches.length > 0) { delvis++; boernBlokerede += k.boern.length; }
  else { uloeselige++; boernBlokerede += k.boern.length; }
}
console.log(`\n  forældrepar der kan løses fuldt i fladen i dag: ${heltLoesbare}  → ${boernLoesbare} børn`);
console.log(`  delvist (mindst én part har intet bog-nummer):  ${delvis}`);
console.log(`  slet ikke (begge mangler bog-nummer):           ${uloeselige}`);
console.log(`  børn der forbliver blokerede:                   ${boernBlokerede}`);

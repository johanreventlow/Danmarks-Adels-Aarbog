// Seedet, syntetisk feed-input til ekvivalenstesten (order.ekvivalens.test.ts) og målingen (scripts/maal-order.ts).
// Ingen projektdata: personer, hændelser, embeder og besiddelser er opfundne. Generatoren skubber bevidst til
// rytmereglernes kanter — mange 'naevnt', få eller ingen portrætter, mange kort for samme person (R2), puljer med kun
// én korttype (R1), dagens person med egne kort, ens scores, dublerede og ukendte pins, seenWeights 0.
import { buildModel, type ParentChild, type Union } from '@daa/core';
import { mulberry32 } from '../prng';
import { TEMP_DISABLED_KINDS } from '../score';
import type { FeedAux, FeedCard, FeedInputs, HaendelserBy, LivsdatoBy, Model, StorieBy } from '../types';

const UDEN_NAEVNT_SLAAET_FRA = new Set([...TEMP_DISABLED_KINDS].filter((k) => k !== 'naevnt'));

export interface GenOpts {
  persons: number;
  // Andel personer uden tekst/titel (→ 'naevnt'-kandidater) og med brugbar bio (→ portræt/citat).
  naevntAndel?: number;
  bioAndel?: number;
  // Web-feedets form FØR naevnt blev slået fra (24/11): TEMP_DISABLED_KINDS uden 'naevnt' + naevntGrundlag, så
  // naevnt-grenene i trækningsløkken stadig dækkes af ekvivalenstesten.
  webForm?: boolean;
  // Alle korttyper slået til (ingen disabledKinds) — til målingen.
  alleTyper?: boolean;
}

const LONG_BIO = 'Dette er en tilstrækkelig lang og velformet biografisk tekst om personens liv, '
  + 'virke og eftermæle, skrevet med tilstrækkeligt mange detaljer og sammenhæng.';
const KLAUSUL = 'En tilstrækkelig lang klausul om personens historiske liv og virke i slægten.';

export function genFeedInput(seed: number, opts: GenOpts): { model: Model; aux: FeedAux; inputs: FeedInputs } {
  const r = mulberry32(seed ^ 0x5eed);
  const pick = <T>(xs: readonly T[]): T => xs[Math.floor(r() * xs.length)];
  const n = opts.persons;
  const naevntAndel = opts.naevntAndel ?? r();
  const bioAndel = opts.bioAndel ?? r() * r();
  const todayISO = pick(['2026-07-18', '2026-01-01', '2026-03-14', '2026-12-31']);
  const todayYear = Number(todayISO.slice(0, 4));

  const persons = [];
  const sourcesBy: Model['sourcesBy'] = {};
  const livsdatoBy: LivsdatoBy = {};
  const haendelserBy: HaendelserBy = {};
  const storieBy: StorieBy = {};
  const officesBy: FeedAux['officesBy'] = {};
  for (let i = 0; i < n; i++) {
    // Id'er med blandet længde, så id-sortering (localeCompare/byIdStr) ikke er triviel.
    const id = String(i * 7 + (i % 3));
    const u = r();
    const harBio = u < bioAndel;
    const naevnt = !harBio && u < bioAndel + naevntAndel;
    const born = r() < 0.1 ? null : 1500 + Math.floor(r() * 400);
    // Få levende/uden dødsevidens (GDPR-gaten i levende.ts skal også have noget at fjerne).
    const died = r() < 0.05 ? null : born != null ? born + Math.floor(r() * 80) : todayYear - 100 - Math.floor(r() * 300);
    persons.push({
      id, name: 'Person ' + id, born, died, years: '', title: !harBio && !naevnt && r() < 0.5 ? 'Kammerherre' : '',
      bio: harBio ? LONG_BIO + ' ' + id : naevnt ? '' : (r() < 0.5 ? 'Kort.' : ''),
      privat: r() < 0.03,
    });
    if (r() < 0.9) sourcesBy[id] = [{ ref: `Linje I, nr. ${id}`, work: 'DAA 1939' }];
    if (!naevnt) {
      if (r() < 0.3) {
        haendelserBy[id] = Array.from({ length: 1 + Math.floor(r() * 3) }, (_, k) => ({
          id: `h${id}-${k}`, klausul: KLAUSUL, kategori: null,
          dato: { min: null, max: null, qualifier: null }, dateRaw: null,
          interessant: r() < 0.3, rygrad: r() < 0.2, kilde: null,
        }));
      }
      if (r() < 0.05) {
        storieBy[id] = [{
          id: `s${id}`, titel: null, tekst: 'En kort redaktionel minihistorie om personens liv og virke.',
          dato: { min: null, max: null, qualifier: null }, dateRaw: null, haendelseId: null, publiceretDato: null, kilde: null,
        }];
      }
      if (r() < 0.2) {
        // Somme tider mange embeder for samme person → R2 må relakseres.
        const antal = r() < 0.1 ? 10 + Math.floor(r() * 15) : 1 + Math.floor(r() * 3);
        officesBy[id] = Array.from({ length: antal }, (_, k) => ({ label: `Embede ${k % 4}`, period: '', _y: 1600 + k }));
      }
      if (born != null && r() < 0.2) {
        const md = todayISO.slice(5);
        livsdatoBy[id] = { foedt: { min: `${born}-${md}`, max: `${born}-${md}`, qualifier: null } };
      }
    }
  }
  const unions: Union[] = [];
  const parentChild: ParentChild[] = [];
  for (let i = 1; i < n; i++) {
    if (r() < 0.3) {
      const p1 = persons[Math.floor(r() * i)].id;
      const p2 = r() < 0.5 ? persons[Math.floor(r() * i)].id : null;
      const uid = 'f' + i;
      if (p2 !== p1) unions.push({ id: uid, p1, p2, p2_name: null, year: r() < 0.5 ? 1600 + i : null });
      parentChild.push({ child: persons[i].id, parent: p1, union: uid });
    }
  }
  const base = buildModel({ persons, unions, parentChild }) as unknown as Model;
  const model: Model = { ...base, sourcesBy };

  const aux: FeedAux = {
    godsListe: Array.from({ length: Math.floor(r() * Math.min(40, n / 4 + 1)) }, (_, k) => ({ id: String(k), navn: 'Gods ' + k, slags: 'gods', ownerCount: Math.floor(r() * 5) })),
    vaabenListe: Array.from({ length: Math.floor(r() * 3) }, (_, k) => ({ id: String(k), blasonering: '', note: '' })),
    officesBy,
  };

  const ids = persons.map((p) => p.id);
  // Ét fast kort-id-sæt at pinne/skjule/se fra: id'er der faktisk opstår + ét, der aldrig gør.
  const kortIds = ids.flatMap((id) => [`portrait:${id}`, `naevnt:${id}`, `arkiv:h${id}-0`]).concat(['ukendt:1', 'gods:0', 'vaaben:0']);
  const pins = r() < 0.4
    ? Array.from({ length: Math.floor(r() * 5) }, () => ({ kortNoegle: kortIds.length ? pick(kortIds) : 'ukendt:1', handling: r() < 0.6 ? 'pin' as const : 'skjul' as const }))
    : undefined;
  if (pins && pins.length > 0 && r() < 0.5) pins.push({ ...pins[0] }); // dublet
  const seenWeights: Record<string, number> = {};
  if (r() < 0.5) {
    for (let k = 0; k < Math.min(30, kortIds.length); k++) seenWeights[pick(kortIds)] = pick([0, 0.25, 0.5, 1]);
  }
  const alleKinds: FeedCard['kind'][] = ['historie', 'portrait', 'paadennedag', 'dagensperson', 'jubilaeum', 'slaegt',
    'gods', 'embede', 'forbundet', 'arkiv', 'citat', 'vaaben', 'naevnt'];
  const disabledKinds: ReadonlySet<FeedCard['kind']> | undefined = opts.webForm
    ? UDEN_NAEVNT_SLAAET_FRA
    : opts.alleTyper ? undefined : pick([undefined, TEMP_DISABLED_KINDS, new Set(alleKinds.filter(() => r() < 0.3)), new Set(alleKinds.filter((k) => k !== 'naevnt' && k !== 'embede'))]);
  // Ofte et beslægtet par (barn/forælder), så slægtskortet og dets positionslås opstår.
  const par = parentChild.length && r() < 0.6 ? pick(parentChild) : null;
  const meId = par ? par.child : ids.length && r() < 0.6 ? pick(ids) : null;
  const focusId = par ? par.parent : ids.length && r() < 0.7 ? pick(ids) : null;
  const inputs: FeedInputs = {
    seed: Math.floor(r() * 2 ** 31), todayISO, meId, focusId,
    bookmarkedIds: ids.filter(() => r() < 0.05),
    seenWeights, livsdatoBy, haendelserBy, storieBy, pins, disabledKinds,
    naevntGrundlag: opts.webForm || r() < 0.7 ? { personerMedMereEndNavn: new Set(ids.filter(() => r() < 0.1)) } : undefined,
  };
  return { model, aux, inputs };
}

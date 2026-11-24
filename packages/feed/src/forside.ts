// Forsidens minimumskrav til personer (spec docs/superpowers/specs/2026-11-24-forside-minimumskrav-design.md,
// projektejeren 24/11). Gælder kun forsiden — personsiden viser stadig alle offentlige personer. Anvendes oven på
// GDPR-gaten i levende.ts (kun sikkert døde) og kun når FeedInputs.forsideKrav er sat.
import { UDEN_NAVN, UNAVNGIVET_BARN } from '@daa/core';
import { LEVENDE_ALDERSGRAENSE } from './levende';
import type { FeedAux, HaendelserBy, Model } from './types';

type ModelPerson = Model['persons'][number];

export const FORSIDE_MIN_BIO = 200;
export const FORSIDE_MIN_ALDER = 15;
export const FORSIDE_MIN_AAR_DOED = 25;

export type ForsideKontekst = {
  dagsAar: number;
  haendelserBy: HaendelserBy;
  officesBy: FeedAux['officesBy'];
  // Krav 4's billed-gren. Web sender det først med spor 2 (billederne fra 2018-20-PDF'en).
  personerMedBillede?: ReadonlySet<string>;
};

// Et rollenavn i parentes (»(Søn)«), »N. N.« eller visningens pladsholder for en person uden navn (»Unavngivet barn«,
// »(uden navn)«, @daa/core personNavn.ts) er ikke et navn. »(Anna?)« er et usikkert, men rigtigt navn.
const ROLLENAVN = /^\(\s*(søn|datter|barn|dreng|pige)\s*\)/i;
const NN = /^N\.\s?N\./i;

export function harRigtigtNavn(name: string): boolean {
  const n = name.trim();
  if (n === UNAVNGIVET_BARN || n === UDEN_NAVN) return false;
  return !ROLLENAVN.test(n) && !NN.test(n);
}

// Bogens »† ung«/»† lille«/»spæd« betyder død som barn. Ukendt alder udelukker ikke (mange ældre mangler fødselsår).
const DOED_SOM_BARN = /(^|[^\p{L}])(ung|lille|spæd)([^\p{L}]|$)/iu;

export function blevVoksen(p: ModelPerson): boolean {
  if (p.doedTekst && DOED_SOM_BARN.test(p.doedTekst)) return false;
  // Spændene: web opløser »† s.d.«/»† s.å.« mod fødslen i doedSpaend, mens died forbliver null. Øvre dødsår mod nedre
  // fødselsår, så en usikker dato tæller i hele sin bredde (»† 1706/1720« for en født 1700 er voksen).
  const doed = p.doedSpaend?.[1] ?? p.died;
  const foedt = p.foedtSpaend?.[0] ?? p.born;
  if (foedt != null && doed != null) return doed - foedt >= FORSIDE_MIN_ALDER;
  return true;
}

// Død for mindst 25 år siden. Et dødsspænd (»† 1999/2003«) tæller med sit øvre år. Uden dødsår kræves fødsel så
// længe siden, at personen også var død for 25 år siden (levende-grænsen + 25).
export function doedForLaengeSiden(p: ModelPerson, dagsAar: number): boolean {
  const doedsaar = p.doedSpaend?.[1] ?? p.died;
  if (doedsaar != null) return dagsAar - doedsaar >= FORSIDE_MIN_AAR_DOED;
  return p.born != null && dagsAar - p.born >= LEVENDE_ALDERSGRAENSE + FORSIDE_MIN_AAR_DOED;
}

// Noget at fortælle: biografi, titel, embede, en hændelse der kan blive et kort (ikke rygrad), eller et billede.
export function harIndhold(p: ModelPerson, k: ForsideKontekst): boolean {
  if (p.bio.trim().length >= FORSIDE_MIN_BIO) return true;
  if (p.title.trim() !== '') return true;
  if ((k.officesBy[p.id]?.length ?? 0) > 0) return true;
  if ((k.haendelserBy[p.id] ?? []).some((h) => !h.rygrad)) return true;
  return k.personerMedBillede?.has(p.id) ?? false;
}

export function erForsideVaerdig(p: ModelPerson, k: ForsideKontekst): boolean {
  return harRigtigtNavn(p.name) && blevVoksen(p) && doedForLaengeSiden(p, k.dagsAar) && harIndhold(p, k);
}

// Som kunSikkertDoede: udtynder persons/byId; indexes røres ikke (slægtskabsstien skal kunne gå gennem alle).
export function kunForsideVaerdige(model: Model, k: ForsideKontekst): Model {
  const persons = model.persons.filter((p) => erForsideVaerdig(p, k));
  const byId: Model['byId'] = {};
  for (const p of persons) byId[p.id] = p;
  return { ...model, persons, byId };
}

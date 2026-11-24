// Bygger forsidens færdigpakkede fil som gæst og afgør, hvor længe CDN'et må gemme den (spec
// 2026-11-24-forside-data-cache-design.md). Kun de rå svar; browseren kører de eksisterende bygge-funktioner.
import { FORSIDE_DATA_VERSION, type Del, type ForsideData } from './format';
import {
  bladrHaendelser, hentBioKontrakt, hentBioRaekker, hentHistorieRaekker, hentLivsdatoRaekker, hentNaevntSubjekter,
  hentPersonIder, type Sb,
} from './kilder';

const del = <T>(r: PromiseSettledResult<T>, komplet: (v: T) => boolean = () => true): Del<T> =>
  r.status === 'fulfilled' ? { komplet: komplet(r.value), data: r.value } : { komplet: false, data: null };

export async function byggForsideData(sb: Sb, nu: Date): Promise<ForsideData> {
  const personIder = await hentPersonIder(sb);
  const haendelserLoefte = bladrHaendelser(sb);
  const [bios, haendelser, livsdato, historier, naevnt] = await Promise.allSettled([
    hentBioKontrakt(sb).then((k) => hentBioRaekker(sb, k, personIder)),
    haendelserLoefte,
    hentLivsdatoRaekker(sb),
    hentHistorieRaekker(sb),
    hentNaevntSubjekter(sb, haendelserLoefte),
  ]);
  return {
    version: FORSIDE_DATA_VERSION,
    genereret: nu.toISOString(),
    personIder: personIder.map(String),
    bios: del(bios, (b) => b.fejlede.length === 0),
    haendelser: del(haendelser),
    livsdato: del(livsdato),
    historier: del(historier),
    naevnt: del(naevnt),
  };
}

export type ForsideDataSvar = { status: number; headers: Record<string, string>; body: string };

const JSON_TYPE = 'application/json; charset=utf-8';

// Cache-regel: alt komplet → en time (+ et døgn med gammel fil, mens en ny bygges); en del helt mangler → intet gemmes
// (503), så CDN'et ikke holder en dårlig fil; noget delvist (fx en bid biografier) → højst 5 min.
export async function forsideDataSvar(sb: Sb, nu: Date): Promise<ForsideDataSvar> {
  let fd: ForsideData;
  try {
    fd = await byggForsideData(sb, nu);
  } catch (e) {
    console.warn('[forside-data] kunne ikke bygges:', e);
    return { status: 503, headers: { 'content-type': JSON_TYPE, 'cache-control': 'no-store' }, body: JSON.stringify({ fejl: 'utilgængelig' }) };
  }
  const dele = [fd.bios, fd.haendelser, fd.livsdato, fd.historier, fd.naevnt];
  const cache = dele.some((d) => d.data === null)
    ? 'no-store'
    : dele.every((d) => d.komplet)
      ? 'public, s-maxage=3600, stale-while-revalidate=86400'
      : 'public, s-maxage=300, stale-while-revalidate=3600';
  return {
    status: cache === 'no-store' ? 503 : 200,
    headers: { 'content-type': JSON_TYPE, 'cache-control': cache },
    body: JSON.stringify(fd),
  };
}

// Pakker forsidens fil ud til de fem kilder, forsiden bruger (spec 2026-11-24-forside-data-cache-design.md), med de
// samme bygge-funktioner som den direkte hentning. Filen er op til en time gammel: dækker den ikke modellen (en
// ikke-levende person, hvis række ikke stod i filen), eller er en del ufuldstændig, bruges den aldrig som bevis for
// fravær — så intet nævnt-grundlag.
import { buildHaendelserBy, buildLivsdatoBy, buildStorieBy } from '@daa/feed';
import type { HaendelserBy, LivsdatoBy, NaevntGrundlag, StorieBy } from '@daa/feed';
import type { FeedBios } from '../feedAux';
import { buildNaevntGrundlag } from '../feedGrundlag';
import type { ForsideData } from './format';
import { buildFeedBioSubjectIds, vaelgFeedBios } from './kilder';

export type UdpakketForside = {
  bios: FeedBios | null;
  livsdatoBy: LivsdatoBy;
  haendelserBy: HaendelserBy;
  storieBy: StorieBy;
  naevntGrundlag: NaevntGrundlag | 'fejlet';
};

export function udpakForsideData(
  fd: ForsideData,
  model: { canonicalIdById: Record<string, string>; persons: readonly { id: string; levende?: boolean }[] },
): UdpakketForside {
  const canon = model.canonicalIdById;
  const bios = fd.bios.data ? { bioBy: vaelgFeedBios(fd.bios.data, canon), komplet: fd.bios.komplet } : null;
  const h = fd.haendelser.data;
  const l = fd.livsdato.data;
  const s = fd.historier.data;
  const kendte = new Set(fd.personIder);
  const ikkeLevende = model.persons.filter((p) => !p.levende).map((p) => p.id);
  const daekker = buildFeedBioSubjectIds(canon, ikkeLevende).every((id) => kendte.has(id));
  const alleKomplette = [fd.bios, fd.haendelser, fd.historier, fd.naevnt].every((d) => d.komplet && d.data !== null);
  return {
    bios,
    livsdatoBy: l ? buildLivsdatoBy(l.facts, l.conclusions, l.assertions, canon) : {},
    haendelserBy: h ? buildHaendelserBy(h.rows, h.narrativer, h.sources, canon) : {},
    storieBy: s ? buildStorieBy(s.rows, s.kilder, s.sources, canon) : {},
    naevntGrundlag: alleKomplette && daekker && fd.naevnt.data ? buildNaevntGrundlag(fd.naevnt.data, canon) : 'fejlet',
  };
}

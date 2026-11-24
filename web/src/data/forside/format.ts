// Formatet på forsidens færdigpakkede fil (spec 2026-11-24-forside-data-cache-design.md). Versionen hæves, når formen
// ændres, så en gammel fil i CDN'et afvises efter en deploy.
import type { BioRaekker, HaendelseRowsResult, LivsdatoRows, StoryRowsResult, SubjektRow } from './kilder';

export const FORSIDE_DATA_VERSION = 1;

// En del af filen: `data: null` = delen kunne slet ikke hentes; `komplet: false` med data = noget mangler (fx en bid
// biografier). Et ufuldstændigt resultat er aldrig bevis for fravær.
export type Del<T> = { komplet: boolean; data: T | null };

export type ForsideData = {
  version: typeof FORSIDE_DATA_VERSION;
  genereret: string; // ISO-tidspunkt
  personIder: string[]; // de person-rækker, gæsten kunne se, da filen blev bygget
  bios: Del<BioRaekker>;
  haendelser: Del<HaendelseRowsResult>;
  livsdato: Del<LivsdatoRows>;
  historier: Del<StoryRowsResult>;
  naevnt: Del<SubjektRow[][]>;
};

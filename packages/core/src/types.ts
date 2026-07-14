// Domæne-typer delt af @daa/core's rene helpers (kopieret fra web/mobile's data/types.ts —
// code-identiske mellem apps). Person-id er bigint i basen → konverteres ALTID til streng
// internt (README §8).
export type RawExtId = {
  person_id: number | string;
  source_id: number | string;
  linje: string | null;
  nr: number | null;
  // Generations-koordinater (Task B2 Step 1) — pulled forward for B1's rene helpers.
  slaegtled_lokal?: number | null;
  slaegtled_gennem?: number | null;
  kuld?: string | null;
};
export type RawLineage = {
  source_id: number | string;
  kode: string | null;
  navn: string | null;
  // Forgrenings-id'er (Task B2 Step 1) — pulled forward for B1's rene helpers.
  id?: string | number;
  parent_lineage_id?: string | number | null;
};

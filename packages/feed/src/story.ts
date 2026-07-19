// Publicerede minihistorier: ren join af PostgREST-rækker til kanoniseret StorieBy.
// Pakken forbliver netværksfri; app-lagene ejer al indlæsning.
import { byIdStr } from './pool';
import type { FeedCard, HaendelserBy, Model, StorieBy, StoryItem } from './types';

export interface StoryRow {
  id: string | number;
  subjekt_id: string | number;
  haendelse_id: string | number | null;
  titel: string | null;
  tekst: string;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
  date_raw: string | null;
  status: string;
  publiceret_dato: string | null;
  privat: boolean | null;
}

export interface StoryKildeRow {
  id: string | number;
  story_id: string | number;
  source_id: string | number;
  side: string | number | null;
}

export interface StorySourceRow {
  id: string | number;
  udgave: string | number | null;
}

export function buildStorieBy(
  rows: StoryRow[],
  kilder: StoryKildeRow[],
  sources: StorySourceRow[],
  canonicalIdById: Record<string, string> = {},
): StorieBy {
  const sourceById = new Map(sources.map((source) => [String(source.id), source]));
  const kilderByStory = new Map<string, StoryKildeRow[]>();

  for (const kilde of [...kilder].sort((a, b) => Number(a.id) - Number(b.id))) {
    const key = String(kilde.story_id);
    const list = kilderByStory.get(key);
    if (list) list.push(kilde);
    else kilderByStory.set(key, [kilde]);
  }

  const out: StorieBy = {};
  for (const row of rows) {
    if (row.status !== 'publiceret' || row.privat === true) continue;
    const personId = canonicalIdById[String(row.subjekt_id)] ?? String(row.subjekt_id);
    const kildeDele: string[] = [];

    for (const kilde of kilderByStory.get(String(row.id)) ?? []) {
      const source = sourceById.get(String(kilde.source_id));
      if (source?.udgave == null) continue;
      const side = kilde.side == null ? null : String(kilde.side);
      kildeDele.push(`DAA ${String(source.udgave)}${side == null ? '' : `, s. ${side}`}`);
    }

    const item: StoryItem = {
      id: String(row.id),
      titel: row.titel,
      tekst: row.tekst,
      dato: { min: row.date_min, max: row.date_max, qualifier: row.date_qualifier },
      dateRaw: row.date_raw,
      haendelseId: row.haendelse_id == null ? null : String(row.haendelse_id),
      publiceretDato: row.publiceret_dato,
      kilde: kildeDele.length > 0 ? kildeDele.join(' · ') : null,
    };
    (out[personId] ??= []).push(item);
  }

  for (const items of Object.values(out)) {
    items.sort((a, b) => Number(a.id) - Number(b.id) || a.id.localeCompare(b.id));
  }
  return out;
}

// Ét flagskibs-kort pr. story. Hændelses-id'erne trådes videre, så historie-kortet
// erstatter det tilsvarende citat/arkiv-kort i stedet for at duplikere det.
export function buildStorieKort(
  model: Model,
  storieBy: StorieBy,
  haendelserBy: HaendelserBy,
  todayISO: string,
): { cards: FeedCard[]; usedHaendelseIds: Set<string> } {
  const cards: FeedCard[] = [];
  const usedHaendelseIds = new Set<string>();
  const todayMs = Date.parse(todayISO);

  for (const [personId, items] of Object.entries(storieBy)) {
    if (!model.byId[personId]) continue;
    for (const item of items) {
      if (item.haendelseId != null) usedHaendelseIds.add(item.haendelseId);
      const aarLabel = item.dateRaw != null && item.dateRaw !== ''
        ? item.dateRaw
        : item.dato.min?.slice(0, 4) ?? null;
      const anker = item.haendelseId == null
        ? undefined
        : (haendelserBy[personId] ?? []).find((candidate) => candidate.id === item.haendelseId);
      const dage = item.publiceretDato == null
        ? null
        : (todayMs - Date.parse(item.publiceretDato)) / 86_400_000;
      const nyPubliceret = dage != null && dage >= 0 && dage <= 30;
      cards.push({
        kind: 'historie', id: 'story:' + item.id, personId,
        titel: item.titel, tekst: item.tekst, aarLabel,
        kategori: anker?.kategori ?? null, kilde: item.kilde,
        ...(nyPubliceret ? { nyPubliceret: true as const } : {}),
        kicker: 'Historie',
      });
    }
  }

  return { cards: cards.sort(byIdStr), usedHaendelseIds };
}

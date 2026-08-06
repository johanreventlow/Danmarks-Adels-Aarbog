// Medie-læsning (mediehåndtering Slice 0). Delt af person-portræt/-galleri + objekt-billeder
// (gods/våben). RLS på 'media' + storage.objects skjuler ikke-offentlige rækker/objekter, så en
// almindelig select/signering returnerer kun det den aktuelle rolle må se (fail-closed i basen).
import { supabase } from '../supabase';
import { getAll } from '@daa/core';

export type MediaItem = {
  id: string;
  slags: string;
  titel: string;
  kunstner: string;
  datering: string;
  url: string | null; // kortlivet signed URL til FULD størrelse ('large' — media-rækkens egen storage_path)
  thumbUrl: string | null; // 'thumb'-variant (billedstørrelser 2026-07-05, Slice B3); falder tilbage til url hvis ingen findes
  primaer?: boolean;
  // Medie-metadata (Task 6): berigelse fra fetchMediaFakta, joinet ind i loadMediaItems — se
  // mediaFaktaFelter herunder. RLS betyder en tom berigelse (alle null) er normal for et
  // upubliceret medie (anon ser ingen fakta-rækker for det).
  altTekst: string | null;
  kreditlinje: string | null;
  kildeUrl: string | null;
  kildeInstitution: string | null;
  beskrivelse: string | null;
  teknik: string | null;
  fysiskeMaal: string | null;
  dateringFakt: string | null; // Global Constraint: vinder ALTID over `datering`-kolonnen i visning.
};

type RawMediaRow = {
  id: number; slags: string | null; titel: string | null;
  kunstner: string | null; datering: string | null; storage_path: string | null;
};

// Portræt-egnede slags (til at vælge hovedbilledet på et personkort). Sammenlign altid
// normaliseret (lowercase+trim), så 'Maleri'/'Portræt ' også genkendes.
export const PORTRAIT_SLAGS = new Set(['foto', 'maleri', 'portræt', 'portraet']);
const normSlags = (s: string) => s.trim().toLowerCase();

const SIGN_TTL = 600; // sek. — dækker en detalje-visnings-session.

// TTL-cache (spejler mobile/src/lib/media.ts): genbrug stabile signed URLs mellem visninger, så
// gentagne åbninger hverken re-signerer ELLER får browseren til at re-downloade billed-bytes (ny
// URL-token = cache-miss). Ryddes ved auth-skift — signed URLs er bærer-tokens der virker uafhængigt
// af session indtil udløb, så en bruger efter rolle-skift må ikke genbruge en tidligere brugers URLs.
const cache = new Map<string, { url: string; exp: number }>();
supabase.auth.onAuthStateChange(() => cache.clear());

// Mint signed URLs for en batch stier; returnér path→url. Cache-hits springer signering over.
// Tolerant (fejl → udeladt). Eksporteret: redaktionRead.ts's fetchRedPersonMedia genbruger den
// (redaktørens session ser via redaktion_read/media_obj_redaktion-politikkerne ALLE upload_status,
// signering går derfor bare på storage_path uanset offentlig-gating).
export async function signPaths(paths: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const now = Date.now();
  const need: string[] = [];
  for (const p of new Set(paths.filter(Boolean))) {
    const c = cache.get(p);
    if (c && c.exp > now) out.set(p, c.url);
    else need.push(p);
  }
  if (!need.length) return out;
  try {
    const { data, error } = await supabase.storage.from('media').createSignedUrls(need, SIGN_TTL);
    if (error) { console.warn('[media] signering fejlede:', error); return out; }
    for (const row of data ?? []) {
      if (row.signedUrl && row.path) {
        out.set(row.path, row.signedUrl);
        cache.set(row.path, { url: row.signedUrl, exp: now + (SIGN_TTL - 30) * 1000 });
      }
    }
  } catch (e) {
    console.warn('[media] signering kastede:', e);
  }
  return out;
}

// Billedstørrelser (2026-07-05, Slice B3+C): variant-stien pr. media-id for én tier. Delt af
// loadMediaItems (thumb), redaktionRead.ts's mediaFromRelPairs (thumb) og fetchMediaByIds (medium,
// Slice C — narrativ-indlejrede billeder) — én forespørgselsform, parametriseret på tier, i stedet
// for at hver tier får sin egen kopi (/simplify-fund, Slice B3, udvidet her til at dække tier som
// parameter fremfor kun 'thumb').
async function fetchVariantPathByMediaId(mediaIds: Array<number | string>, tier: 'thumb' | 'medium'): Promise<Map<string, string>> {
  if (!mediaIds.length) return new Map();
  const variants = await getAll<{ media_id: number | string; storage_path: string }>(() =>
    supabase.from('media_variant').select('media_id,storage_path').eq('tier', tier).in('media_id', mediaIds));
  return new Map(variants.map((v) => [String(v.media_id), v.storage_path]));
}

export function fetchThumbPathByMediaId(mediaIds: Array<number | string>): Promise<Map<string, string>> {
  return fetchVariantPathByMediaId(mediaIds, 'thumb');
}

// Fælles: hent media-rækker for et sæt id'er, signér, og map til MediaItem (rækkefølge = mediaIds).
// Rækker fra FØR Slice B har ingen variant-række; thumbUrl falder da tilbage til den fulde url.
// Medie-metadata (Task 6): fetchMediaFakta batches parallelt med de to øvrige queries — den fælles
// hale for BÅDE fetchPersonMedia og fetchObjectMedia (begge løber gennem fetchMediaByRelation →
// loadMediaItems), så én berigelse her dækker begge retninger uden dublering.
async function loadMediaItems(mediaIds: number[]): Promise<MediaItem[]> {
  if (!mediaIds.length) return [];
  const [rows, thumbPathByMediaId, faktaByMediaId] = await Promise.all([
    getAll<RawMediaRow>(() =>
      supabase.from('media').select('id,slags,titel,kunstner,datering,storage_path').in('id', mediaIds)),
    fetchThumbPathByMediaId(mediaIds),
    fetchMediaFakta(mediaIds),
  ]);
  const signed = await signPaths([
    ...rows.map((r) => r.storage_path ?? ''),
    ...thumbPathByMediaId.values(),
  ].filter(Boolean));
  const byId = new Map(rows.map((r) => [r.id, r]));
  return mediaIds
    .map((id) => byId.get(id))
    .filter((r): r is RawMediaRow => !!r)
    .map((r) => {
      const url = r.storage_path ? signed.get(r.storage_path) ?? null : null;
      const thumbPath = thumbPathByMediaId.get(String(r.id));
      return {
        id: String(r.id), slags: r.slags ?? '', titel: r.titel ?? '',
        kunstner: r.kunstner ?? '', datering: r.datering ?? '',
        url, thumbUrl: (thumbPath ? signed.get(thumbPath) : null) ?? url,
        ...mediaFaktaFelter(faktaByMediaId.get(String(r.id))),
      };
    });
}

// Én batchet primitiv for BEGGE retninger af 'afbildet' (retningen er en parameter, ikke en forket
// funktion): returnér ankerId → MediaItem[] i ÉN relation+media+sign-triade. Selv-tolerant: en
// medie-/storage-fejl må ikke vælte en safe()-ombrudt forælder (som ville blanke bio/embeder/godser).
//   · person→media (mediaSide='objekt'): media_afbilder_skjult forudsætter denne retning (GDPR).
//   · media→objekt (mediaSide='subjekt'): gods/våben/… (intet person-gating).
async function fetchMediaByRelation(opts: {
  mediaSide: 'subjekt' | 'objekt'; ankerType: string; ankerIds: number[];
}): Promise<Map<string, MediaItem[]>> {
  const byAnker = new Map<string, MediaItem[]>();
  if (!opts.ankerIds.length) return byAnker;
  const ankerSide = opts.mediaSide === 'objekt' ? 'subjekt' : 'objekt'; // ankeret sidder modsat media
  try {
    const rels = await getAll<{ subjekt_id: number; objekt_id: number; kvalifikator: { primaer?: boolean } | null }>(() =>
      supabase.from('relation').select('subjekt_id,objekt_id,kvalifikator')
        .eq(`${ankerSide}_type`, opts.ankerType).in(`${ankerSide}_id`, opts.ankerIds)
        .eq(`${opts.mediaSide}_type`, 'media').eq('rolle', 'afbildet'));
    const mediaIdOf = (r: { subjekt_id: number; objekt_id: number }) => opts.mediaSide === 'objekt' ? r.objekt_id : r.subjekt_id;
    const ankerIdOf = (r: { subjekt_id: number; objekt_id: number }) => opts.mediaSide === 'objekt' ? r.subjekt_id : r.objekt_id;
    const items = await loadMediaItems([...new Set(rels.map(mediaIdOf))]);
    const itemById = new Map(items.map((it) => [it.id, it]));
    for (const r of rels) {
      const it = itemById.get(String(mediaIdOf(r)));
      if (!it) continue;
      const k = String(ankerIdOf(r));
      const arr = byAnker.get(k) ?? [];
      arr.push(r.kvalifikator?.primaer === true ? { ...it, primaer: true } : it);
      byAnker.set(k, arr);
    }
  } catch (e) {
    console.warn('[media] fetchMediaByRelation fejlede:', e);
  }
  return byAnker;
}

// Dedup pr. media-id, men lad 'primaer:true' ALDRIG tabes til rækkefølge. Baggrund: samme medie kan
// have en separat 'afbildet'-relationsrække pr. foldet samme_som-alias (relation_afbildet_uidx
// håndhæver kun unikhed pr. enkelt (person,media)-par, ikke på tværs af en foldet persongruppe) — én
// alias kan have kvalifikator.primaer=true, den anden ikke, og der er ingen ORDER BY der garanterer
// hvilken af de to kommer først fra fetchMediaByRelation. Et naivt "første forekomst vinder"-filter
// kan derfor stille slette redaktørens portræt-valg, hvis den ikke-primaer kopi behandles først.
// Løsning: en forekomst med primaer=true overskriver altid en tidligere ikke-primaer forekomst af
// samme id — men en senere ikke-primaer forekomst overskriver ALDRIG en allerede-set primaer=true.
export function dedupPreferPrimaer(items: MediaItem[]): MediaItem[] {
  const byId = new Map<string, MediaItem>();
  for (const it of items) {
    const existing = byId.get(it.id);
    if (!existing || (it.primaer === true && existing.primaer !== true)) byId.set(it.id, it);
  }
  return [...byId.values()];
}

// Personens billeder (portræt+materiale): union over foldede medlems-id'er, dedup pr. media-id.
export async function fetchPersonMedia(numIds: number[]): Promise<MediaItem[]> {
  const byPerson = await fetchMediaByRelation({ mediaSide: 'objekt', ankerType: 'person', ankerIds: numIds });
  return dedupPreferPrimaer([...byPerson.values()].flat());
}

// Objekt-billeder (gods/våben/…), batchet: ankerId → MediaItem[].
export function fetchObjectMedia(objektType: string, objektIds: number[]): Promise<Map<string, MediaItem[]>> {
  return fetchMediaByRelation({ mediaSide: 'subjekt', ankerType: objektType, ankerIds: objektIds });
}

// Første viste (signerbare) billede — delt "brug det første brugbare"-kontrakt.
export function firstSignable(media: MediaItem[]): MediaItem | null {
  return media.find((m) => m.url) ?? null;
}

// Filtrér til rækker med en signeret url + typesnævr til ikke-null url. Delt af pickPortrait
// herunder og af Lightbox-kaldere (Folgesvend.tsx/Redaktion.tsx), der skal bygge en navigerbar,
// url-bærende liste uden hver at gentage den samme type-guard (/simplify-fund, Slice A).
export function withUrl<T extends { url: string | null }>(items: (T | null | undefined)[]): (T & { url: string })[] {
  return items.filter((m): m is T & { url: string } => !!m?.url);
}

// Vælg hovedbillede: eksplicit portræt-valg (primaer, fase 4/M10) → slags-heuristik → første med URL.
export function pickPortrait(media: MediaItem[]): MediaItem | null {
  const signable = withUrl(media);
  return signable.find((m) => m.primaer === true)
    ?? signable.find((m) => PORTRAIT_SLAGS.has(normSlags(m.slags)))
    ?? signable[0] ?? null;
}

// Billedtekst: titel · kunstner · datering (kun de udfyldte). Delt af MediaThumb (primitives.tsx)
// og Lightbox — samme formel, ét sted (/simplify-fund, Slice A). Global Constraint (medie-metadata
// Task 6): `dateringFakt` (den strukturerede fakt) vinder ALTID over den rå `datering`-kolonne i
// visning, hvis begge er sat.
export function mediaCaption(m: { titel?: string | null; kunstner?: string | null; datering?: string | null; dateringFakt?: string | null }): string {
  return [m.titel, m.kunstner, m.dateringFakt ?? m.datering].filter(Boolean).join(' · ');
}

// Billeder indlejret i narrativer (billedstørrelser 2026-07-05, Slice C). Et [[media:ID|...]]-
// token kan pege på ET VILKÅRLIGT media-id — ikke nødvendigvis en del af den viste subjekts egen
// portræt/galleri-liste (fx et linje-våben nævnt inde i en persons bio) — derfor et selvstændigt
// opslag i stedet for at genbruge fetchPersonMedia/fetchObjectMedia (som begge forudsætter en
// relations-sti til et kendt anker). RLS gør resten: et id der er slettet/skjult kommer bare ikke
// tilbage fra `media`-selectet og udelades stille (renderer'en viser det som inaktiv gråtekst).
export type EmbeddedMedia = { titel: string; mediumUrl: string; largeUrl: string };

// Medie-fakta (medie-metadata, Task 2): strukturerede fakta på 'media' som subjekt — kildeoplysninger,
// fotograf, kreditlinje, teknik osv. SKRIVE-whitelist (12 koder — de 3 rettigheds-koder skrives
// fortsat via red_set_media_rettigheder, se redaktionWrite.ts) + LÆSE-union (MM-03: 12 + de 3
// eksisterende rettigheds-koder, så et redigerings-overlay kan præudfylde dem sammen).
export const MEDIA_FAKTATYPER = ['kilde_url', 'kilde_institution', 'ekstern_objekt_id', 'hentedato',
  'fotograf', 'rettighedshaver', 'kreditlinje', 'beskrivelse', 'alt_tekst', 'teknik', 'fysiske_maal', 'datering'] as const;
export const MEDIA_FAKTA_LAES = [...MEDIA_FAKTATYPER, 'licens', 'kildehenvisning', 'gengivelsestilladelse'] as const;
export type MediaFaktatype = typeof MEDIA_FAKTATYPER[number];
export type MediaFaktaLaesKode = typeof MEDIA_FAKTA_LAES[number];
export type MediaFaktaVaerdi = {
  factId: string; vaerdi: string | null;
  dateMin: string | null; dateMax: string | null; dateQualifier: string | null; dateRaw: string | null;
};
export type MediaFakta = Partial<Record<MediaFaktaLaesKode, MediaFaktaVaerdi>>;

// Ren mapper: MediaFakta → MediaItem's berigelses-felter. Delt af loadMediaItems (person-/objekt-
// medier) og feedMedia.ts's fetchFeedMediaCandidates (kun altTekst-feltet derfra) — udtrukket så
// felt-til-felt-mapningen (og dateringFakt's dateRaw??vaerdi-forrang) testes ét sted, uafhængigt af
// Supabase. `fakta` er undefined når mediet ikke har nogen (RLS-gatede/upublicerede medier — normalt).
export function mediaFaktaFelter(fakta: MediaFakta | undefined): {
  altTekst: string | null; kreditlinje: string | null; kildeUrl: string | null;
  kildeInstitution: string | null; beskrivelse: string | null;
  teknik: string | null; fysiskeMaal: string | null; dateringFakt: string | null;
} {
  return {
    altTekst: fakta?.alt_tekst?.vaerdi ?? null,
    kreditlinje: fakta?.kreditlinje?.vaerdi ?? null,
    kildeUrl: fakta?.kilde_url?.vaerdi ?? null,
    kildeInstitution: fakta?.kilde_institution?.vaerdi ?? null,
    beskrivelse: fakta?.beskrivelse?.vaerdi ?? null,
    teknik: fakta?.teknik?.vaerdi ?? null,
    fysiskeMaal: fakta?.fysiske_maal?.vaerdi ?? null,
    dateringFakt: fakta?.datering?.dateRaw ?? fakta?.datering?.vaerdi ?? null,
  };
}

type RawMediaFact = { id: number; subjekt_id: number; faktatype: string };
type RawMediaAssert = {
  id: number; target_id: number; vaerdi_tekst: string | null;
  date_min: string | null; date_max: string | null; date_qualifier: string | null; date_raw: string | null;
};
type RawMediaConc = { target_id: number; valgt_assertion_id: number | null; status?: string };

// Ren/testbar: joiner fact→assertion via conclusion.valgt_assertion_id, gruppér pr. media-id
// (fact.subjekt_id) → faktatype. MM-02: en conclusion-række med status sat men ≠ 'afklaret'
// ignoreres defensivt — fetchMediaFakta filtrerer allerede i selecten, men join-funktionen skal
// ikke stole blindt på det (fx hvis kaldt med ufiltrerede rows fra et andet sted).
export function joinMediaFakta(
  facts: RawMediaFact[], assertions: RawMediaAssert[], conclusions: RawMediaConc[],
): Map<string, MediaFakta> {
  const out = new Map<string, MediaFakta>();
  const assertById = new Map(assertions.map((a) => [a.id, a]));
  const concByFact = new Map(conclusions.map((c) => [c.target_id, c]));
  for (const f of facts) {
    const conc = concByFact.get(f.id);
    if (!conc || conc.valgt_assertion_id == null) continue;
    if (conc.status != null && conc.status !== 'afklaret') continue;
    const a = assertById.get(conc.valgt_assertion_id);
    if (!a) continue;
    const faktatype = f.faktatype as MediaFaktaLaesKode;
    const mediaId = String(f.subjekt_id);
    const fakta = out.get(mediaId) ?? {};
    fakta[faktatype] = {
      factId: String(f.id), vaerdi: a.vaerdi_tekst,
      dateMin: a.date_min, dateMax: a.date_max, dateQualifier: a.date_qualifier, dateRaw: a.date_raw,
    };
    out.set(mediaId, fakta);
  }
  return out;
}

// Henter medie-fakta for et sæt media-id'er. Spejler fetchPersonEvidence-mønsteret
// (redaktionRead.ts:129-142): fact-select på subjekt_type='media' → assertion/conclusion på
// target_type='fact'. MM-02: conclusion-selecten filtrerer eksplicit .eq('status','afklaret') —
// red_tilbagetraek_fakta beholder valgt_assertion_id (schema.sql:1379-1380), så uden filteret
// ville "fjernede" værdier fortsat vises. RLS afgør synlighed (anon ser kun publicerede mediers fakta).
export async function fetchMediaFakta(mediaIds: number[]): Promise<Map<string, MediaFakta>> {
  if (!mediaIds.length) return new Map();
  const { data: facts } = await supabase
    .from('fact').select('id,subjekt_id,faktatype')
    .eq('subjekt_type', 'media').in('subjekt_id', mediaIds).in('faktatype', MEDIA_FAKTA_LAES);
  const factIds = (facts ?? []).map((f: RawMediaFact) => f.id);
  if (!factIds.length) return new Map();
  const [{ data: assertions }, { data: conclusions }] = await Promise.all([
    supabase.from('assertion').select('id,target_id,vaerdi_tekst,date_min,date_max,date_qualifier,date_raw')
      .eq('target_type', 'fact').in('target_id', factIds),
    supabase.from('conclusion').select('target_id,valgt_assertion_id,status')
      .eq('target_type', 'fact').in('target_id', factIds).eq('status', 'afklaret'),
  ]);
  return joinMediaFakta(
    (facts ?? []) as RawMediaFact[],
    (assertions ?? []) as RawMediaAssert[],
    (conclusions ?? []) as RawMediaConc[],
  );
}

export async function fetchMediaByIds(mediaIds: number[]): Promise<Map<string, EmbeddedMedia>> {
  const out = new Map<string, EmbeddedMedia>();
  if (!mediaIds.length) return out;
  const [rows, mediumPathByMediaId] = await Promise.all([
    getAll<{ id: number; titel: string | null; storage_path: string | null }>(() =>
      supabase.from('media').select('id,titel,storage_path').in('id', mediaIds)),
    fetchVariantPathByMediaId(mediaIds, 'medium'),
  ]);
  const signed = await signPaths([
    ...rows.map((r) => r.storage_path ?? ''),
    ...mediumPathByMediaId.values(),
  ].filter(Boolean));
  for (const r of rows) {
    if (!r.storage_path) continue; // uden storage_path er der intet at vise uanset variant
    const largeUrl = signed.get(r.storage_path);
    if (!largeUrl) continue; // ikke signerbar (fx storage-fejl) → udelades, renderes som inaktiv
    const mediumPath = mediumPathByMediaId.get(String(r.id));
    const mediumUrl = (mediumPath ? signed.get(mediumPath) : null) ?? largeUrl;
    out.set(String(r.id), { titel: r.titel ?? '', mediumUrl, largeUrl });
  }
  return out;
}

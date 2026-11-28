// Port af buildAux() fra design-HTML (linje 808-868). Bygger hjælpe-indekser pr. person:
// kilder (bogreference + citations-faldback), embeder/godser (relation), medier. Linjerne bor siden 6e (batch 4) på
// modellen (model.lineage, data/udgaveLag.ts): nøglet på den kanoniske linje, ikke på den trykte kode.
import { buildProvenanceSources, compareDanish, erIkkeGods, estateArtEtiket, estateKanonisk, flettKilder, MAJORAT_SLAGS, parseYear, stripParen, type CitationProvenanceRow, type EstateSlags, type SourceRef } from '@daa/core';
import { findMedieDubletKandidatIds, klassificerMedie, type MedieKoe } from './redaktionRead';
import { dedupPreferPrimaer } from '../lib/media';
import type {
  Aux,
  EstateDetalje,
  RawArms,
  RawEstate,
  RawMedia,
  RawOrg,
  RawRelation,
  RawSource,
  RawTextMention,
} from './types';

type BuildAuxInput = {
  // Bogens opslag pr. kanonisk person (buildSources i udgaveLag, = model.sourcesBy). Allerede kanoniseret.
  bogKilder?: Record<string, SourceRef[]>;
  sources: RawSource[];
  relations: RawRelation[];
  mediaRelations?: RawRelation[];
  mediaMentions?: RawTextMention[];
  estates: RawEstate[];
  // estate→estate-relationer (sammenlagt_i, hører_under); udeladt/tom = som før #471.
  godsRelationer?: RawRelation[];
  orgs: RawOrg[];
  media: RawMedia[];
  arms?: RawArms[];
  // Proveniens fra evidenslaget (citation→source). Bruges KUN for personer uden bog-nummer —
  // se flettKilder. Mirror af web/src/data/public.ts's fetchProveniens.
  citationKilder?: CitationProvenanceRow[];
};

// Antal forskellige ejere (kanoniske person-id'er): en ejer med to perioder tæller én gang, som web's antalEjere.
const antalEjere = (ejere: readonly { personId: string }[]): number => new Set(ejere.map((o) => o.personId)).size;

export function buildAux(
  {
    bogKilder,
    sources,
    relations,
    mediaRelations,
    mediaMentions,
    estates,
    godsRelationer,
    orgs,
    media,
    arms,
    citationKilder,
  }: BuildAuxInput,
  // samme_som-collapse: alle person-id-bærende strukturer kanoniseres, så hjælpedata for en foldet
  // person samles under den kanoniske id (spec §8). Default {} for bagudkompat i eksisterende tests.
  canonicalIdById: Record<string, string> = {},
): Aux {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const estById: Record<string, string> = {};
  (estates || []).forEach((e) => {
    estById[String(e.id)] = e.navn ?? '';
  });
  const orgById: Record<string, string> = {};
  (orgs || []).forEach((o) => {
    orgById[String(o.id)] = o.navn ?? '';
  });

  // Ægtefæller har intet bog-nummer og fik derfor ingen kilde vist. Deres proveniens står i
  // citationerne — bog-nummeret vinder hvor det findes.
  const sourcesBy: Aux['sourcesBy'] = flettKilder(
    bogKilder ?? {},
    buildProvenanceSources(citationKilder ?? [], canonicalIdById),
  );

  // Embeder/godser fra relation (kun subjekt_type=person — loaderen filtrerer allerede).
  const estatesBy: Aux['estatesBy'] = {};
  const officesBy: Aux['officesBy'] = {};
  const estById2: Record<string, RawEstate> = {};
  (estates || []).forEach((e) => {
    estById2[String(e.id)] = e;
  });
  const ownersByEstate: Aux['ownersByEstate'] = {};

  (relations || []).forEach((r) => {
    const pid = cid(String(r.subjekt_id));
    const per = stripParen(r.periode_raw);
    if (r.objekt_type === 'estate') {
      // »Ikke et gods« (#471): rækken og ejerforholdet bevares, men personen får ikke en besiddelse at vise.
      if (!erIkkeGods(estById2[String(r.objekt_id)]?.slags)) {
        (estatesBy[pid] = estatesBy[pid] || []).push({
          id: String(r.objekt_id),
          navn: estById[String(r.objekt_id)] || 'Gods #' + r.objekt_id,
          period: per,
          personId: String(r.subjekt_id),
        });
      }
      if ((r.rolle || '').toLowerCase() === 'ejer') {
        (ownersByEstate[String(r.objekt_id)] = ownersByEstate[String(r.objekt_id)] || []).push({
          personId: pid,
          period: per,
          _y: parseYear(r.periode_raw) || 9999,
        });
      }
    } else if (r.objekt_type === 'organisation' || r.objekt_type === 'historical_event') {
      const org = orgById[String(r.objekt_id)] || '';
      const role = (r.rolle || '').trim();
      const label =
        org && org.toLowerCase() !== role.toLowerCase()
          ? role
            ? role + ', ' + org
            : org
          : role;
      (officesBy[pid] = officesBy[pid] || []).push({
        label,
        period: per,
        _y: parseYear(r.periode_raw) || 9999,
      });
    }
  });
  Object.values(officesBy).forEach((arr) => arr.sort((a, b) => a._y - b._y));

  // Gods→gods (#471): sammenlagte rækker følger den overlevende; gård → majorat vises som »hører under«.
  const sammenlagt = new Map<string, string>();
  (godsRelationer || []).forEach((r) => {
    if (r.rolle === 'sammenlagt_i' && r.subjekt_type === 'estate' && r.objekt_type === 'estate') sammenlagt.set(String(r.subjekt_id), String(r.objekt_id));
  });
  // Som web: en sammenlægning, der danner kreds, er ingen sammenlægning — rækken forbliver sig selv.
  const kanon = (id: string): string => {
    const k = estateKanonisk(id, sammenlagt);
    return sammenlagt.has(k) ? id : k;
  };
  const erSammenlagt = (id: string) => kanon(id) !== id;
  const hoererUnderRaa: { gaard: string; majorat: string; periode: string }[] = [];
  const set = new Set<string>();
  (godsRelationer || []).forEach((r) => {
    if (r.rolle !== 'hører_under' || r.subjekt_type !== 'estate' || r.objekt_type !== 'estate') return;
    const gaard = kanon(String(r.subjekt_id)), majorat = kanon(String(r.objekt_id));
    const nøgle = `${gaard}|${majorat}|${r.periode_raw ?? ''}`;
    if (gaard === majorat || !estById2[gaard] || !estById2[majorat] || set.has(nøgle)) return;
    set.add(nøgle);
    hoererUnderRaa.push({ gaard, majorat, periode: r.periode_raw ?? '' });
  });
  const navnFor = (id: string) => estById2[id]?.navn || 'Gods #' + id;
  const detalje = (eid: string): EstateDetalje => {
    const e = estById2[eid] || { id: eid, navn: 'Gods #' + eid, slags: '' };
    const slags = e.slags || '';
    const erMajorat = MAJORAT_SLAGS.has(slags as EstateSlags);
    const omfattede = erMajorat
      ? hoererUnderRaa.filter((h) => h.majorat === eid).map((h) => ({ id: h.gaard, navn: navnFor(h.gaard) }))
        .filter((g, i, arr) => arr.findIndex((x) => x.id === g.id) === i)
      : [];
    const hoererUnder = erMajorat ? [] : hoererUnderRaa.filter((h) => h.gaard === eid).map((h) => ({ id: h.majorat, navn: navnFor(h.majorat), periode: h.periode }));
    return { id: eid, navn: e.navn || 'Gods #' + eid, slags, art: estateArtEtiket(e.slags ?? null), hoererUnder, omfattede };
  };

  // Gods-oversigt: kun godser med registrerede ejere (sammenlagte rækker er ikke selvstændige godser).
  const estateById: Aux['estateById'] = {};
  const estateList: Aux['estateList'] = Object.keys(ownersByEstate)
    .filter((eid) => !erSammenlagt(eid))
    .flatMap((eid) => {
      const d = detalje(eid);
      estateById[eid] = d;
      ownersByEstate[eid].sort((a, b) => a._y - b._y);
      // Rækker markeret »ikke et gods« står ikke i oversigten, men er i estateById (direkte link til /estate/<id>; #471).
      return erIkkeGods(d.slags) ? [] : [{ id: eid, navn: d.navn, ownerCount: antalEjere(ownersByEstate[eid]) }];
    })
    .sort((a, b) => compareDanish(a.navn, b.navn));
  // Gamle (sammenlagte) id'er viser den overlevende; ejere hentes på det kanoniske id (estate.id).
  Object.keys(estById2).filter(erSammenlagt).forEach((eid) => { estateById[eid] = estateById[kanon(eid)] ?? detalje(kanon(eid)); });
  // Også en »ikke et gods«-række uden registrerede ejere kan åbnes direkte.
  Object.keys(estById2).filter((eid) => erIkkeGods(estById2[eid].slags) && !estateById[eid]).forEach((eid) => { estateById[eid] = detalje(eid); });

  // Medier pr. person: relation person(subjekt) → media(objekt), rolle 'afbildet' (samme retning
  // som DB'ens afbildet-gating). media-rækken slås op på id. RLS har allerede skjult ikke-offentlige
  // rækker. (Tidligere nøglede denne på m.person_id — en kolonne der ikke findes i skemaet → altid tom.)
  const mediaById: Record<string, RawMedia> = {};
  (media || []).forEach((m) => {
    if (m.id != null) mediaById[String(m.id)] = m;
  });
  const mediaBy: Aux['mediaBy'] = {};
  (relations || []).forEach((r) => {
    if (r.objekt_type !== 'media' || (r.rolle || '') !== 'afbildet') return;
    const m = mediaById[String(r.objekt_id)];
    if (m) {
      const pid = cid(String(r.subjekt_id));
      (mediaBy[pid] = mediaBy[pid] || []).push(
        r.kvalifikator?.primaer === true ? { ...m, primaer: true } : m,
      );
    }
  });
  Object.keys(mediaBy).forEach((pid) => {
    mediaBy[pid] = dedupPreferPrimaer(mediaBy[pid]);
  });

  // Flade entitets-lister (2C-1, read-only browse). Rene mappings, dansk-sorteret.
  const kildeListe = (sources || []).map((s) => ({
    id: String(s.id), titel: s.titel ?? '', slags: s.slags ?? '', udgave: s.udgave ?? '',
  })).sort((a, b) => compareDanish(a.titel, b.titel));
  const orgListe = (orgs || []).map((o) => ({
    id: String(o.id), navn: o.navn ?? '(uden navn)', slags: o.slags ?? '',
  })).sort((a, b) => compareDanish(a.navn, b.navn));
  const afbildetByMediaId = new Map<string, Set<string>>();
  for (const r of [...(relations || []), ...(mediaRelations || [])]) {
    if (r.rolle !== 'afbildet') continue;
    const pair = r.subjekt_type === 'person' && r.objekt_type === 'media'
      ? { mediaId: String(r.objekt_id), target: `person:${r.subjekt_id}` }
      : r.subjekt_type === 'media' && ['estate','coat_of_arms','lineage'].includes(r.objekt_type)
        ? { mediaId: String(r.subjekt_id), target: `${r.objekt_type}:${r.objekt_id}` }
        : null;
    if (pair) {
      const targets = afbildetByMediaId.get(pair.mediaId) ?? new Set<string>();
      targets.add(pair.target);
      afbildetByMediaId.set(pair.mediaId, targets);
    }
  }
  const antalMentionsById = new Map<string, number>();
  for (const mention of mediaMentions || []) {
    if (mention.maal_type !== 'media') continue;
    const mediaId = String(mention.maal_id);
    antalMentionsById.set(mediaId, (antalMentionsById.get(mediaId) ?? 0) + 1);
  }
  const dubletKandidatIds = findMedieDubletKandidatIds(media || []);
  const medieListe = (media || []).map((m) => {
    const id = String(m.id ?? '');
    const uploadStatus = m.upload_status ?? 'kladde';
    const maaPubliceres = Boolean(m.maa_publiceres);
    const rettighederStatus = m.rettigheder_status ?? 'ukendt';
    const antalAfbildet = afbildetByMediaId.get(id)?.size ?? 0;
    const antalMentions = antalMentionsById.get(id) ?? 0;
    return {
      id, titel: String(m.titel ?? ''), slags: String(m.slags ?? ''),
      kunstner: String(m.kunstner ?? ''), datering: String(m.datering ?? ''),
      storagePath: String(m.storage_path ?? ''), thumbStoragePath: String(m.thumb_storage_path ?? ''), mimeType: String(m.mime_type ?? ''),
      uploadStatus, maaPubliceres, rettighederStatus, antalAfbildet, antalMentions,
      koeer: klassificerMedie(
        { uploadStatus, maaPubliceres, rettighederStatus },
        antalAfbildet,
        antalMentions,
        dubletKandidatIds.has(id),
      ),
    };
  }).sort((a, b) => compareDanish(a.titel, b.titel));
  const medieKoeTaellere: Record<MedieKoe, number> = {
    rettigheder: 0,
    loese: 0,
    strandede: 0,
    papirkurv: 0,
    dubletter: 0,
  };
  medieListe.forEach((m) => m.koeer.forEach((koe) => { medieKoeTaellere[koe] += 1; }));
  // godsListe: KOMPLET (alle estates, ikke kun ejede); ownerCount fra ownersByEstate (0 hvis ingen).
  const godsListe = (estates || []).filter((e) => !erSammenlagt(String(e.id)) && !erIkkeGods(e.slags)).map((e) => ({
    id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '',
    ownerCount: antalEjere(ownersByEstate[String(e.id)] || []),
  })).sort((a, b) => compareDanish(a.navn, b.navn));
  const vaabenListe = (arms || []).map((a) => ({
    id: String(a.id), blasonering: a.blasonering ?? '', note: a.note ?? '',
  })).sort((a, b) => compareDanish(a.blasonering, b.blasonering));

  return {
    sourcesBy,
    estatesBy,
    officesBy,
    mediaBy,
    mediaById,
    ownersByEstate,
    estateList,
    estateById,
    kildeListe,
    orgListe,
    medieListe,
    medieKoeTaellere,
    godsListe,
    vaabenListe,
  };
}

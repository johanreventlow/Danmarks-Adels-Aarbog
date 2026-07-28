// Port af buildAux() fra design-HTML (linje 808-868). Bygger hjælpe-indekser pr. person:
// kilder (bogreference), embeder/godser (relation), linjer (grene I–V), medier.
import { buildProvenanceSources, compareDanish, flettKilder, parseYear, stripParen, type CitationProvenanceRow } from '@daa/core';
import { findMedieDubletKandidatIds, klassificerMedie, type MedieKoe } from './redaktionRead';
import { dedupPreferPrimaer } from '../lib/media';
import type {
  Aux,
  RawArms,
  RawEstate,
  RawExtId,
  RawLineage,
  RawMedia,
  RawOrg,
  RawRelation,
  RawSource,
  RawTextMention,
} from './types';

type BuildAuxInput = {
  extIds: RawExtId[];
  sources: RawSource[];
  relations: RawRelation[];
  mediaRelations?: RawRelation[];
  mediaMentions?: RawTextMention[];
  estates: RawEstate[];
  orgs: RawOrg[];
  media: RawMedia[];
  lineage?: RawLineage[];
  arms?: RawArms[];
  // Proveniens fra evidenslaget (citation→source). Bruges KUN for personer uden bog-nummer —
  // se flettKilder. Mirror af web/src/data/public.ts's fetchProveniens.
  citationKilder?: CitationProvenanceRow[];
};

export function buildAux(
  {
    extIds,
    sources,
    relations,
    mediaRelations,
    mediaMentions,
    estates,
    orgs,
    media,
    lineage,
    arms,
    citationKilder,
  }: BuildAuxInput,
  // samme_som-collapse: alle person-id-bærende strukturer kanoniseres, så hjælpedata for en foldet
  // person samles under den kanoniske id (spec §8). Default {} for bagudkompat i eksisterende tests.
  canonicalIdById: Record<string, string> = {},
): Aux {
  const cid = (id: string) => canonicalIdById[id] ?? id;
  const srcById: Record<string, RawSource> = {};
  (sources || []).forEach((s) => {
    srcById[String(s.id)] = s;
  });
  const estById: Record<string, string> = {};
  (estates || []).forEach((e) => {
    estById[String(e.id)] = e.navn ?? '';
  });
  const orgById: Record<string, string> = {};
  (orgs || []).forEach((o) => {
    orgById[String(o.id)] = o.navn ?? '';
  });

  // Kilder pr. person: trykt værk + "Linje X, nr. N". Nøgle kanoniseres → union pr. foldet person.
  const bogKilder: Aux['sourcesBy'] = {};
  (extIds || []).forEach((x) => {
    const src = srcById[String(x.source_id)] || ({} as RawSource);
    const work = src.titel || src.udgave || 'Kilde';
    const place = [x.linje ? 'Linje ' + x.linje : '', x.nr != null ? 'nr. ' + x.nr : '']
      .filter(Boolean)
      .join(', ');
    const pid = cid(String(x.person_id));
    (bogKilder[pid] = bogKilder[pid] || []).push({ ref: place, work });
  });
  // Ægtefæller har intet bog-nummer og fik derfor ingen kilde vist. Deres proveniens står i
  // citationerne — bog-nummeret vinder hvor det findes.
  const sourcesBy: Aux['sourcesBy'] = flettKilder(
    bogKilder,
    buildProvenanceSources(citationKilder ?? [], canonicalIdById),
  );

  // Linjer (grene): hver person hører til en (eller flere) linje(r); hver linje har en stamfader
  // (laveste nr). En collapsed grundlægger tilhører både oprindelses- og grundlagt-linje.
  const linjeByPerson: Aux['linjeByPerson'] = {};
  const linjeCounts: Record<string, number> = {};
  const linjeHead: Record<string, { id: string; nr: number }> = {};
  (extIds || []).forEach((x) => {
    if (!x.linje) return;
    const pid = cid(String(x.person_id));
    const arr = (linjeByPerson[pid] = linjeByPerson[pid] || []);
    // Tæl distinkte kanoniske personer pr. linje (ikke ext-rækker), så en foldet person med
    // flere rækker i samme linje ikke inflaterer count.
    if (!arr.includes(x.linje)) {
      arr.push(x.linje);
      linjeCounts[x.linje] = (linjeCounts[x.linje] || 0) + 1;
    }
    const cur = linjeHead[x.linje];
    const nr = x.nr == null ? 9999 : x.nr;
    if (!cur || nr < cur.nr) linjeHead[x.linje] = { id: pid, nr };
  });
  // Linje-navne fra lineage-tabellen (kode → navn). Fallback til kode hvis tabellen mangler/tom.
  const linjeNavn: Aux['linjeNavn'] = {};
  (lineage || []).forEach((l) => {
    if (l.kode && l.navn) linjeNavn[l.kode] = l.navn;
  });
  const linjeList: Aux['linjeList'] = Object.keys(linjeCounts)
    .sort()
    .map((l) => ({
      linje: l,
      count: linjeCounts[l],
      headId: linjeHead[l]?.id ?? null,
      navn: linjeNavn[l] ?? null,
    }));

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
      (estatesBy[pid] = estatesBy[pid] || []).push({
        navn: estById[String(r.objekt_id)] || 'Gods #' + r.objekt_id,
        period: per,
      });
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

  // Gods-oversigt: kun godser med registrerede ejere.
  const estateById: Aux['estateById'] = {};
  const estateList: Aux['estateList'] = Object.keys(ownersByEstate)
    .map((eid) => {
      const e = estById2[eid] || { id: eid, navn: 'Gods #' + eid, slags: '' };
      const navn = e.navn || 'Gods #' + eid;
      estateById[eid] = { id: eid, navn, slags: e.slags || '' };
      ownersByEstate[eid].sort((a, b) => a._y - b._y);
      return { id: eid, navn, ownerCount: ownersByEstate[eid].length };
    })
    .sort((a, b) => compareDanish(a.navn, b.navn));

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
  const godsListe = (estates || []).map((e) => ({
    id: String(e.id), navn: e.navn ?? '(uden navn)', slags: e.slags ?? '',
    ownerCount: (ownersByEstate[String(e.id)] || []).length,
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
    linjeByPerson,
    linjeList,
    linjeNavn,
    kildeListe,
    orgListe,
    medieListe,
    medieKoeTaellere,
    godsListe,
    vaabenListe,
  };
}

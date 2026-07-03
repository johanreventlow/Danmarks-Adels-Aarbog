// Port af buildAux() fra design-HTML (linje 808-868). Bygger hjælpe-indekser pr. person:
// kilder (bogreference), embeder/godser (relation), linjer (grene I–V), medier.
import { compareDanish } from '../lib/collation';
import { parseYear, stripParen } from './fields';
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
} from './types';

type BuildAuxInput = {
  extIds: RawExtId[];
  sources: RawSource[];
  relations: RawRelation[];
  estates: RawEstate[];
  orgs: RawOrg[];
  media: RawMedia[];
  lineage?: RawLineage[];
  arms?: RawArms[];
};

export function buildAux(
  {
    extIds,
    sources,
    relations,
    estates,
    orgs,
    media,
    lineage,
    arms,
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
  const sourcesBy: Aux['sourcesBy'] = {};
  (extIds || []).forEach((x) => {
    const src = srcById[String(x.source_id)] || ({} as RawSource);
    const work = src.titel || src.udgave || 'Kilde';
    const place = [x.linje ? 'Linje ' + x.linje : '', x.nr != null ? 'nr. ' + x.nr : '']
      .filter(Boolean)
      .join(', ');
    const pid = cid(String(x.person_id));
    (sourcesBy[pid] = sourcesBy[pid] || []).push({ ref: place, work });
  });

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

  // Medier pr. person (tom indtil medier linkes).
  const mediaBy: Aux['mediaBy'] = {};
  (media || []).forEach((m) => {
    const pid = m.person_id != null ? cid(String(m.person_id)) : null;
    if (pid) (mediaBy[pid] = mediaBy[pid] || []).push(m);
  });

  // Flade entitets-lister (2C-1, read-only browse). Rene mappings, dansk-sorteret.
  const kildeListe = (sources || []).map((s) => ({
    id: String(s.id), titel: s.titel ?? '', slags: s.slags ?? '', udgave: s.udgave ?? '',
  })).sort((a, b) => compareDanish(a.titel, b.titel));
  const orgListe = (orgs || []).map((o) => ({
    id: String(o.id), navn: o.navn ?? '(uden navn)', slags: o.slags ?? '',
  })).sort((a, b) => compareDanish(a.navn, b.navn));
  const medieListe = (media || []).map((m) => ({
    id: String((m as { id?: unknown }).id ?? ''), titel: String((m as { titel?: unknown }).titel ?? ''),
    slags: String((m as { slags?: unknown }).slags ?? ''), kunstner: String((m as { kunstner?: unknown }).kunstner ?? ''),
    datering: String((m as { datering?: unknown }).datering ?? ''),
  })).sort((a, b) => compareDanish(a.titel, b.titel));
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
    ownersByEstate,
    estateList,
    estateById,
    linjeByPerson,
    linjeList,
    linjeNavn,
    kildeListe,
    orgListe,
    medieListe,
    godsListe,
    vaabenListe,
  };
}

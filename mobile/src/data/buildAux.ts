// Port af buildAux() fra design-HTML (linje 808-868). Bygger hjælpe-indekser pr. person:
// kilder (bogreference), embeder/godser (relation), linjer (grene I–V), medier.
import { parseYear, stripParen } from './fields';
import type {
  Aux,
  RawEstate,
  RawExtId,
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
};

export function buildAux({
  extIds,
  sources,
  relations,
  estates,
  orgs,
  media,
}: BuildAuxInput): Aux {
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

  // Kilder pr. person: trykt værk + "Linje X, nr. N".
  const sourcesBy: Aux['sourcesBy'] = {};
  (extIds || []).forEach((x) => {
    const src = srcById[String(x.source_id)] || ({} as RawSource);
    const work = src.titel || src.udgave || 'Kilde';
    const place = [x.linje ? 'Linje ' + x.linje : '', x.nr != null ? 'nr. ' + x.nr : '']
      .filter(Boolean)
      .join(', ');
    (sourcesBy[String(x.person_id)] = sourcesBy[String(x.person_id)] || []).push({
      ref: place,
      work,
    });
  });

  // Linjer (grene): hver person hører til en linje; hver linje har en stamfader (laveste nr).
  const linjeByPerson: Aux['linjeByPerson'] = {};
  const linjeCounts: Record<string, number> = {};
  const linjeHead: Record<string, { id: string; nr: number }> = {};
  (extIds || []).forEach((x) => {
    if (!x.linje) return;
    linjeByPerson[String(x.person_id)] = x.linje;
    linjeCounts[x.linje] = (linjeCounts[x.linje] || 0) + 1;
    const cur = linjeHead[x.linje];
    const nr = x.nr == null ? 9999 : x.nr;
    if (!cur || nr < cur.nr) linjeHead[x.linje] = { id: String(x.person_id), nr };
  });
  const linjeList: Aux['linjeList'] = Object.keys(linjeCounts)
    .sort()
    .map((l) => ({ linje: l, count: linjeCounts[l], headId: linjeHead[l]?.id ?? null }));

  // Embeder/godser fra relation (kun subjekt_type=person — loaderen filtrerer allerede).
  const estatesBy: Aux['estatesBy'] = {};
  const officesBy: Aux['officesBy'] = {};
  const estById2: Record<string, RawEstate> = {};
  (estates || []).forEach((e) => {
    estById2[String(e.id)] = e;
  });
  const ownersByEstate: Aux['ownersByEstate'] = {};

  (relations || []).forEach((r) => {
    const pid = String(r.subjekt_id);
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
    .sort((a, b) => a.navn.localeCompare(b.navn, 'da'));

  // Medier pr. person (tom indtil medier linkes).
  const mediaBy: Aux['mediaBy'] = {};
  (media || []).forEach((m) => {
    const pid = m.person_id != null ? String(m.person_id) : null;
    if (pid) (mediaBy[pid] = mediaBy[pid] || []).push(m);
  });

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
  };
}

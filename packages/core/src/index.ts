export * from './generations';
export * from './getAll';
export * from './collation';
export * from './mentions';
export * from './fields';
export * from './pickPreferredBio';
export * from './bioVersions';
export * from './relationship';
export * from './collapseSameAs';
export * from './placementCoordinates';
export { FAKTA_UDELADT, buildPersonFacts } from './personFacts';
export type { PublicPersonFactRow, PersonFactSource, PersonFactStatement, PersonFactView } from './personFacts';
export { byggUdgaveFakta, udgaveForRaekker, udgaverMedFakta } from './editionFacts';
export type { KunIUdgave, Udgave, UdgaveFaktaInput, UdgaveFaktaLinje, UdgaveFaktaVisning, UdgaveNote } from './editionFacts';
export * from './editionSelector';
export * from './factEquality';
export { erRelativDato, oploesRelativDato } from './relativeDates';
export type { OploesValg } from './relativeDates';
export * from './sammeSomPreflight';
export * from './buildFamilyGraph';
export * from './buildGeo';
export * from './geoSelectors';
export * from './buildModel';
export * from './tree';
export * from './navnevarianter';
export * from './matchUdgaver';
export * from './kildeProveniens';
export * from './linjeVisning';
export * from './slaegtsrod';
export * from './slaegter';
export * from './entityDescriptions';
export * from './presensLabels';
export * from './presensListe';
export * from './ocrKvalitet';
export * from './physicalPersonIds';
export * from './familieKilder';
export * from './vielse';
export * from './recordLabel';
export { KONFIDENS_VALUES, KONFIDENS_RANK } from './types';
export type {
  RawExtId,
  RawLineage,
  RawSource,
  LineageContext,
  RawLineageContext,
  RawLineageScheme,
  RawLineageSchemeEntry,
  RawLineageSchemeEntryLineage,
  SlaegtRef,
  LineageRef,
  LineageSchemeEntryRef,
  EntityDescription,
  CoatOfArmsAssociation,
  RawEstate,
  RawPlace,
  RawFact,
  Union,
  ParentChild,
  Koen,
  Konfidens,
  AppPerson,
  Db,
  SameAsEdge,
  Provenance,
  QuarantineNote,
  CollapseResult,
  ModelPerson,
  ModelIndexes,
  Model,
  Lineage,
  SourceRef,
  LinjeEntry,
  GeoKind,
  GeoPoint,
  Geo,
} from './types';
export * from './b6Note';
export * from './bogensOrden';
export * from './kunIAeldreUdgave';
export * from './personNavn';
export { slutterPaaSlaegtsnavn, udenSlaegtsnavnTilSidst } from './slaegtsnavn';
export { ADELS_TITLER, erAdelsTitel } from './adelsTitler';
export { adelsnavnForLinjer, byggLinjeAdelsnavne, formelNavneform, lineageIdAfNoegle, personensAdelsnavn } from './adelsnavn';
export type { LinjeAdelsnavne } from './adelsnavn';
export * from './sletVej';
export * from './mediaVisning';
// 6e-projektionen (linjer, udgaver, kilder) — flyttet fra web/src/data (mobil-paritet, batch 3).
export * from './lineage';
export * from './linjeRaekker';
export * from './udgaver';
export * from './stamtavleKilder';
export * from './sources';
export * from './kunIAeldre';
// Familieblokken i bogens rækkefølge — flyttet fra web/src/data (mobil-paritet, batch 6).
export * from './modelTraversering';
export * from './konfTekst';
export * from './fokusTrae';
export * from './faktaVisning';
// Slægtskab som kontekst over navnet og »Er vi i familie?«-teksterne — flyttet fra web/src/data (mobil-paritet, batch 7).
export * from './slaegtskab';
export * from './omSlaegten';
export * from './godserIUdgave';
// Besiddelsens ejerrække og ejertal — flyttet fra web/src/data (mobil-paritet, bid 9).
export * from './ejerraekke';
// Søgningens match, levetid, filtre og stavemåder — flyttet fra web/src/data/soeg.ts (mobil-paritet, bid 9).
export * from './soeg';

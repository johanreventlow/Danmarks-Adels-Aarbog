// Review 37 R37B-4: historie-editorens datokvalifikator som valgfelt i stedet for fritekst. Værdierne er netop dem,
// story_date_qualifier_chk tillader (schema.sql); testen datoKvalifikatorer.test.ts holder de to i takt.
export const STORY_DATO_KVALIFIKATORER: ReadonlyArray<readonly [string, string]> = [
  ['', 'Kvalifikator: ikke sat'],
  ['exact', 'præcis'],
  ['about', 'ca.'],
  ['before', 'før'],
  ['after', 'efter'],
  ['between', 'mellem'],
  ['floruit', 'virksom (fl.)'],
  ['until_event', 'indtil hændelse'],
  ['open_end', 'åben slutning'],
  ['ongoing', 'igangværende'],
];

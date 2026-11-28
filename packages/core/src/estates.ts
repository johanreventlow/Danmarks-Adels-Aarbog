// Delt visning af godser (web + mobil): godsets art (`estate.slags`).

// Samme fem koder som `vocab` (scheme `estate_slags`), som databasens trigger håndhæver; db-verify.sql låser
// rækkerne til denne liste. Et nyt gods-slags = en vocab-række + en linje her (#471).
export const ESTATE_SLAGS = ['gård', 'grevskab', 'baroni', 'stamhus', 'ikke_gods'] as const;
export type EstateSlags = (typeof ESTATE_SLAGS)[number];

// »Ikke et gods«: bogen nævner intet gods (fx en forlening eller en skænkning). Rækken og dens ejerforhold bliver i
// databasen, men skjules fra lister, søgning, feed, kort og personsider; direkte link viser den stadig (#471).
export function erIkkeGods(slags: string | null | undefined): boolean {
  return slags === 'ikke_gods';
}

// Majoraterne: de bundne formuer (alt andet end en almindelig gård).
export const MAJORAT_SLAGS: ReadonlySet<EstateSlags> = new Set<EstateSlags>(['grevskab', 'baroni', 'stamhus']);

const ETIKETTER: Record<EstateSlags, string> = { gård: 'Gård', grevskab: 'Grevskab', baroni: 'Baroni', stamhus: 'Stamhus', ikke_gods: 'Ikke et gods' };

// Label til visning; NULL og ukendte koder giver null (ingen art at vise).
export function estateArtEtiket(slags: string | null): string | null {
  return slags !== null && Object.prototype.hasOwnProperty.call(ETIKETTER, slags) ? ETIKETTER[slags as EstateSlags] : null;
}

// Følger »sammenlagt_i« fra et sammenlagt gods til det gods, det blev lagt ind i (id'er som tekst). Vagten i databasen
// forhindrer kæder, så ét skridt er normalt; funktionen stopper dog efter 10 skridt og ved en cyklus og giver så det
// sidste id, i stedet for at hænge. Et id uden indgang er sit eget (#471).
export function estateKanonisk(id: string, sammenlagt: ReadonlyMap<string, string>): string {
  const set = new Set<string>([id]);
  let nu = id;
  for (let i = 0; i < 10; i++) {
    const naeste = sammenlagt.get(nu);
    if (naeste === undefined || set.has(naeste)) return nu;
    set.add(naeste);
    nu = naeste;
  }
  return nu;
}

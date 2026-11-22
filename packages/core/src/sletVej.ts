// Review 37 P11 (projektejeren 2026-11-22): én sletteknap, systemet vælger vejen. Databasen afgør i
// red_slet_person_preview, om personen kan slettes, så det kan fortrydes (kun en offentlig person: afdød, ikke privat,
// ikke staged, ikke skjult af sin samme_som-gruppe). Ellers skal den slettes helt (GDPR), og red_slet_person afviser
// med SLET_KRAEVER_SLET_HELT: <årsag>. Teksterne her deles af web og mobil, så de to ikke kan glide fra hinanden.

export type SletAarsag = 'levende' | 'privat' | 'staged' | 'samme_som_skjult' | 'findes_ikke' | 'ukendt';
export type SletVej = { kanFortrydes: boolean; aarsag: SletAarsag | null };

const KENDTE: readonly SletAarsag[] = ['levende', 'privat', 'staged', 'samme_som_skjult', 'findes_ikke', 'ukendt'];
const erAarsag = (v: unknown): v is SletAarsag => typeof v === 'string' && (KENDTE as readonly string[]).includes(v);

// Fail-closed: et svar uden kan_fortrydes (en database fra før P11, eller et forkert svar) giver ALDRIG den
// fortrydelige vej — den kunne gøre skjulte oplysninger offentlige. Så er vejen »Slet helt« med årsagen 'ukendt'.
export function sletVejFraPreview(raw: unknown): SletVej {
  const r = (raw && typeof raw === 'object' ? raw : {}) as { kan_fortrydes?: unknown; aarsag?: unknown };
  if (r.kan_fortrydes === true) return { kanFortrydes: true, aarsag: null };
  return { kanFortrydes: false, aarsag: erAarsag(r.aarsag) ? r.aarsag : 'ukendt' };
}

// Hvorfor personen skal slettes helt, og hvordan man ellers kunne få en sletning, der kan fortrydes.
export function sletAarsagTekst(aarsag: SletAarsag): { hvorfor: string; hvordan: string } {
  switch (aarsag) {
    case 'levende': return {
      hvorfor: 'Personen er markeret som nulevende (eller det er ikke registreret, at personen er død). En nulevendes oplysninger skal slettes helt, også fra historikken.',
      hvordan: 'Er personen død, skal markeringen rettes først — så kan sletningen fortrydes. Markeringen kan ikke rettes i redaktionen i dag; bed den, der vedligeholder databasen, om det.',
    };
    case 'privat': return {
      hvorfor: 'Personen er markeret som privat. Private oplysninger skal slettes helt, også fra historikken.',
      hvordan: 'Skal personen ikke længere være privat, så slå »Privat« fra på personsiden først (så bliver personen synlig for læserne) — så kan sletningen fortrydes.',
    };
    case 'staged': return {
      hvorfor: 'Personen er en uafklaret post fra en ny udgave (fx en mulig dublet), som endnu ikke er afstemt mod de andre udgaver og derfor er skjult for læserne. Den slettes helt, så intet af den bliver stående i historikken.',
      hvordan: 'Først når udgaven er afstemt og publiceret, er posten offentlig — så kan en sletning fortrydes.',
    };
    case 'samme_som_skjult': return {
      hvorfor: 'En anden udgaves registrering af samme person (»samme som«) er nulevende eller privat, så også denne post er skjult for læserne. Den skal derfor slettes helt, også fra historikken.',
      hvordan: 'Er »samme som«-koblingen forkert, så fjern den først — så kan sletningen fortrydes.',
    };
    case 'findes_ikke': return {
      hvorfor: 'Personen findes ikke længere — den er måske allerede slettet.',
      hvordan: 'Genindlæs siden.',
    };
    case 'ukendt': return {
      hvorfor: 'Systemet kunne ikke afgøre, om sletningen kan fortrydes. For en sikkerheds skyld tilbydes kun den fulde sletning.',
      hvordan: 'Hent forhåndsvisningen igen; viser den stadig ingen svar, så brug den fulde sletning.',
    };
  }
}

// SLET_KRAEVER_SLET_HELT: <årsag> fra red_slet_person (personens status ændrede sig mellem forhåndsvisning og klik).
export function sletKraeverSletHelt(message: string): SletAarsag | null {
  const m = /\bSLET_KRAEVER_SLET_HELT\b(?::\s*([a-z_]+))?/.exec(message);
  if (!m) return null;
  return erAarsag(m[1]) ? m[1] : 'ukendt';
}

export function sletKraeverSletHeltTekst(aarsag: SletAarsag): string {
  return `Personen kan ikke længere slettes, så det kan fortrydes — dens status er ændret, siden forhåndsvisningen blev hentet. ${sletAarsagTekst(aarsag).hvorfor} Brug »Slet helt« i stedet. Intet er slettet.`;
}

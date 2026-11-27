// Forsidens krav 8 på mobilen: et billede tæller som indhold (som web). Sættet bygges af de allerede hentede medier.
import { erForsideVaerdig } from '@daa/feed';
import { buildAux } from '../buildAux';
import { personerMedBillede } from '../personerMedBillede';

const media = (id: number) => ({ id, slags: 'portræt', titel: null, kunstner: null, datering: null, storage_path: `p/${id}.jpg`,
  mime_type: 'image/jpeg', upload_status: 'klar', maa_publiceres: true, rettigheder_status: 'ukendt', byte_size: 1, bredde: 1, hoejde: 1, created_at: '' });
const afbildet = (person: number, mediaId: number) =>
  ({ subjekt_type: 'person', subjekt_id: person, objekt_type: 'media', objekt_id: mediaId, rolle: 'afbildet', periode_raw: null });

// Person 10 er afbildet på medie 1; person 11 på medie 2, som læseren ikke må se (RLS gav ingen række); 12 er alias for 10.
const aux = buildAux({
  sources: [], estates: [], orgs: [], arms: [],
  media: [media(1)],
  relations: [afbildet(10, 1), afbildet(11, 2), afbildet(12, 1)],
} as never, { '12': '10' });

describe('personerMedBillede', () => {
  test('kun personer med et billede, læseren må se, under den kanoniske id', () => {
    expect([...personerMedBillede(aux)]).toEqual(['10']);
  });

  test('en person, hvis eneste indhold er et billede, er forsideværdig; uden billedet ikke', () => {
    const p = { id: '10', name: 'Anna Reventlow', title: '', bio: '', born: 1700, died: 1760 } as never;
    const k = { dagsAar: 2026, haendelserBy: {}, officesBy: {} };
    expect(erForsideVaerdig(p, { ...k, personerMedBillede: personerMedBillede(aux) })).toBe(true);
    expect(erForsideVaerdig(p, k)).toBe(false);
  });
});

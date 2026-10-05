import { describe, expect, test } from 'vitest';
import { personaFrames, udenAarstal } from '../frames';

describe('personaFrames', () => {
  test('navn og år fra eksporten; manglende navn giver tom nøgle', () => {
    const { frames, origins } = personaFrames([
      { source_persona_id: 'p1', name: 'Ludvig Reventlow', name_origin: 'accepted_interpretation',
        birth_raw: '12.3.1848', birth_origin: 'proposed_interpretation', death_raw: null, death_origin: null },
      { source_persona_id: 'p2', name: null, name_origin: null, birth_raw: null, birth_origin: null, death_raw: null, death_origin: null },
    ]);
    expect(frames[0]).toMatchObject({ id: 'p1', birthMin: 1848, birthMax: 1848, sex: 'ukendt' });
    expect(frames[0].nameKey.length).toBeGreaterThan(0);
    expect(frames[1].nameKey).toBe('');
    expect(origins.get('p1')).toEqual({ name: 'accepted_interpretation', birth: 'proposed_interpretation', death: null });
  });

  test('uden årstal afgøres af de parsede år, ikke af råfeltets tilstedeværelse', () => {
    const { frames } = personaFrames([
      { source_persona_id: 'p1', name: 'A', name_origin: 'mention', birth_raw: 'uden tal', birth_origin: 'mention', death_raw: null, death_origin: null },
      { source_persona_id: 'p2', name: 'B', name_origin: 'mention', birth_raw: null, birth_origin: null, death_raw: 'd. 1900', death_origin: 'mention' },
      { source_persona_id: 'p3', name: 'C', name_origin: 'mention', birth_raw: null, birth_origin: null, death_raw: null, death_origin: null },
    ]);
    expect(udenAarstal(frames)).toEqual(['p1', 'p3']);
  });
});

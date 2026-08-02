import { describe, expect, it } from 'vitest';
import { buildSourcePersonaDecisionCall } from '../sourcePersona';

describe('buildSourcePersonaDecisionCall', () => {
  it('sender kun en person ved samme identitet og et menneskeligt notat', () => {
    expect(buildSourcePersonaDecisionCall('00000000-0000-0000-0000-000000000001', 2, 'same', 42, 'samme ægtefælle og dato')).toEqual({
      fn: 'red_afgoer_source_persona', args: {
        p_source_persona_id: '00000000-0000-0000-0000-000000000001', p_expected_version: 2,
        p_action: 'same', p_canonical_person_id: 42, p_note: 'samme ægtefælle og dato',
      },
    });
  });

  it.each([
    ['same', null, 'basis'], ['different', 42, 'basis'], ['unresolved', 42, 'basis'],
    ['same', 42, '   '], ['same', 42, 'basis', -1],
  ] as const)('afviser fail-closed ugyldig afgørelse %s', (action, personId, note, version = 0) => {
    expect(buildSourcePersonaDecisionCall('persona', version, action, personId, note)).toBeNull();
  });
});

import { buildRpcCall, FELT_FAKTATYPE } from '../redaktionWrite';

describe('buildRpcCall', () => {
  it('mapper foedt → red_upsert_fakta m. faktatype fødsel', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt: 'foedt',
                vaerdi: '1671', kildeFritekst: 'DAA' } as const;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_upsert_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: 'fødsel',
              p_vaerdi: '1671', p_date_raw: '1671', p_kilde_fritekst: 'DAA' },
    });
  });
  it('koen → red_set_koen (ikke et fact)', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt: 'koen', vaerdi: 'mand' } as const;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_set_koen', args: { p_person_id: 7, p_koen: 'mand' } });
  });
  it('navn → faktatype navn, intet date_raw', () => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '3', felt: 'navn', vaerdi: 'Conrad' } as const;
    expect(buildRpcCall(c)?.args.p_faktatype).toBe('navn');
    expect(buildRpcCall(c)?.args.p_date_raw).toBeUndefined();
  });
  it('FELT_FAKTATYPE har ikke koen (special-case)', () => {
    expect(FELT_FAKTATYPE.koen).toBeUndefined();
  });
});

import { buildRpcCall } from '../redaktionWrite';

// Web-spejl af mobile-testen for de samme_som-arter (identitets-links, spec 2026-07-02).
describe('buildRpcCall — samme_som (identitets-links)', () => {
  it('sammeSom → red_samme_som(p_alias_id,p_objekt_id)', () => {
    const call = buildRpcCall({ art: 'sammeSom', subjektType: 'person', subjektId: '255',
      payload: { aliasId: '255', objektId: '392' } } as never);
    expect(call).toEqual({ fn: 'red_samme_som', args: { p_alias_id: 255, p_objekt_id: 392 } });
  });
  it('fjernSammeSom → red_fjern_samme_som(p_relation_id)', () => {
    const call = buildRpcCall({ art: 'fjernSammeSom', subjektType: 'person', subjektId: '392',
      relationId: '972' } as never);
    expect(call).toEqual({ fn: 'red_fjern_samme_som', args: { p_relation_id: 972 } });
  });
  it('sammeSom uden payload → null', () => {
    expect(buildRpcCall({ art: 'sammeSom', subjektType: 'person', subjektId: '255' } as never)).toBeNull();
  });
});

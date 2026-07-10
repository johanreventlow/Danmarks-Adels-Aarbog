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

// Web-spejl af mobile-testen for uploadMedia (mediehåndtering Slice 0g).
describe('buildRpcCall — uploadMedia (mediehåndtering Slice 0g)', () => {
  it('portræt (afbildetPersonId) → red_upload_media med p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: 'Portræt', maaPubliceres: true,
        storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg',
        byteSize: 1234, originalFilnavn: 'x.jpg' } } as never;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_upload_media', args: {
      p_slags: 'foto', p_titel: 'Portræt', p_storage_path: 'redaktor/x.jpg', p_mime: 'image/jpeg',
      p_byte_size: 1234, p_bredde: null, p_hoejde: null, p_original_filnavn: 'x.jpg',
      p_rettigheder_status: 'ukendt', p_maa_publiceres: true, p_afbildet_person_id: 42 } });
  });
  it('objekt-foto (objektType/objektId) → p_objekt_type/p_objekt_id, ingen p_afbildet_person_id', () => {
    const c = { art: 'uploadMedia', subjektType: 'estate', subjektId: '7',
      payload: { objektType: 'estate', objektId: '7', slags: 'foto', titel: 'Godset',
        storagePath: 'redaktor/y.jpg', mimeType: 'image/jpeg' } } as never;
    const call = buildRpcCall(c);
    expect(call?.fn).toBe('red_upload_media');
    expect(call?.args.p_objekt_type).toBe('estate');
    expect(call?.args.p_objekt_id).toBe(7);
    expect(call?.args.p_afbildet_person_id).toBeUndefined();
  });
  it('mangler titel → null (p_titel har intet DEFAULT i RPC-signaturen)', () => {
    expect(buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42',
      payload: { afbildetPersonId: '42', slags: 'foto', titel: '',
        storagePath: 'redaktor/x.jpg', mimeType: 'image/jpeg' } } as never)).toBeNull();
  });
});

// Web-spejl af mobile-testen for fjernMedia (mediehåndtering Slice 0h).
describe('buildRpcCall — fjernMedia (mediehåndtering Slice 0h)', () => {
  it('fjernMedia → red_fjern_media med p_media_id', () => {
    const c = { art: 'fjernMedia', subjektType: 'person', subjektId: '42', mediaId: '91' } as never;
    expect(buildRpcCall(c)).toEqual({ fn: 'red_fjern_media', args: { p_media_id: 91 } });
  });
  it('mangler mediaId → null', () => {
    expect(buildRpcCall({ art: 'fjernMedia', subjektType: 'person', subjektId: '42' } as never)).toBeNull();
  });
});

describe('buildRpcCall — forældre ukendt-markering (docs/reviews/25)', () => {
  it('markerForaeldreUkendt → red_upsert_fakta med faktatype forældre_ukendt + grad + kilde', () => {
    const call = buildRpcCall({
      art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '210',
      vaerdi: 'forælder ukendt', kildeFritekst: 'DAA 1939 s.97',
    } as never);
    expect(call).toEqual({ fn: 'red_upsert_fakta', args: {
      p_subjekt_type: 'person', p_subjekt_id: 210,
      p_faktatype: 'forældre_ukendt', p_vaerdi: 'forælder ukendt', p_kilde_fritekst: 'DAA 1939 s.97',
    } });
  });

  it('markerForaeldreUkendt uden grad (vaerdi) → null (grad er påkrævet)', () => {
    expect(buildRpcCall({ art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '210' } as never)).toBeNull();
  });

  it('markerForaeldreUkendt uden kilde → p_kilde_fritekst null', () => {
    const call = buildRpcCall({
      art: 'markerForaeldreUkendt', subjektType: 'person', subjektId: '5', vaerdi: 'ingen forbindelse angivet',
    } as never);
    expect(call?.args.p_kilde_fritekst).toBeNull();
  });

  // FJERN af markeringen genbruger den generiske 'sletOplysning'-art (ingen egen fjern-art) —
  // dækket af sletOplysning-testen; her verificeres blot at fjern-call-site'et rammer det rigtige RPC.
  it('fjern via sletOplysning → red_slet_oplysning med assertion-id', () => {
    const call = buildRpcCall({ art: 'sletOplysning', subjektType: 'person', subjektId: '210', assertionId: '801' } as never);
    expect(call).toEqual({ fn: 'red_slet_oplysning', args: { p_assertion_id: 801 } });
  });
});

import { buildRpcCall, FELT_FAKTATYPE, oversaetFejl, planCall } from '../redaktionWrite';

describe('buildRpcCall — udvidede rygrad-felter (dåb/begravelse/floruit/naturalisering)', () => {
  it.each([
    ['daab', 'dåb'], ['begravelse', 'begravelse'], ['floruit', 'floruit'], ['naturalisering', 'naturalisering'],
  ])('%s → red_upsert_fakta m. faktatype %s + p_date_raw', (felt, faktatype) => {
    const c = { art: 'fakta', subjektType: 'person', subjektId: '7', felt, vaerdi: '1680' } as const;
    expect(buildRpcCall(c)).toEqual({
      fn: 'red_upsert_fakta',
      args: { p_subjekt_type: 'person', p_subjekt_id: 7, p_faktatype: faktatype, p_vaerdi: '1680', p_date_raw: '1680' },
    });
  });
  it('FELT_FAKTATYPE dækker de fire nye felter', () => {
    expect(FELT_FAKTATYPE).toMatchObject({
      daab: 'dåb', begravelse: 'begravelse', floruit: 'floruit', naturalisering: 'naturalisering',
    });
  });
});

describe('buildRpcCall — haendelseStatus', () => {
  it('bygger status-RPC og afviser manglende id', () => {
    expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7',
      haendelseId: 91, status: 'skjult' })).toEqual({
        fn: 'red_set_haendelse_status', args: { p_haendelse_id: 91, p_status: 'skjult' },
      });
    expect(buildRpcCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7', status: 'kandidat' })).toBeNull();
    expect(planCall({ art: 'haendelseStatus', subjektType: 'person', subjektId: '7', haendelseId: 91, status: 'skjult' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: { p_payload: { haendelseId: 91, status: 'skjult' } } });
  });
});

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
      p_kunstner: null, p_datering: null, p_byte_size: 1234, p_bredde: null, p_hoejde: null, p_original_filnavn: 'x.jpg',
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

  // FJERN markering (review 26 HIGH 2): tilbagetræk fakta-slottets konklusion via
  // red_tilbagetraek_fakta — IKKE red_slet_oplysning (som re-peger til ældste påstand og
  // genopliver markeringen efter Markér→Opdatér→Fjern). Målretter fact-id'et, ikke en assertion.
  it('tilbagetraekFakta → red_tilbagetraek_fakta med fact-id (fjern markering korrekt)', () => {
    const call = buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '55' } as never);
    expect(call).toEqual({ fn: 'red_tilbagetraek_fakta', args: { p_fact_id: 55 } });
  });

  it('tilbagetraekFakta uden fact-id → null', () => {
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210' } as never)).toBeNull();
  });

  it('tilbagetraekFakta med ugyldigt (ikke-numerisk/tomt) fact-id → null (NaN-guard, review 27)', () => {
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: '' } as never)).toBeNull();
    expect(buildRpcCall({ art: 'tilbagetraekFakta', subjektType: 'person', subjektId: '210', factId: 'x' } as never)).toBeNull();
  });
});

describe('buildRpcCall — forældrefamilie (Problem 2)', () => {
  it('foraeldrePaastand → red_tilfoej_foraeldre_paastand med alle valgfrie args', () => {
    const call = buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12, sourceId: 3, side: 's.490', citat: 'udg. citat' } });
    expect(call).toEqual({ fn: 'red_tilfoej_foraeldre_paastand', args: {
      p_barn_id: 50, p_family_id: 12, p_source_id: 3, p_side: 's.490', p_citat: 'udg. citat' } });
  });
  it('foraeldrePaastand minimal (kun barn+familie) → kun p_barn_id/p_family_id', () => {
    const call = buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50',
      payload: { barnId: 50, familyId: 12 } });
    expect(call).toEqual({ fn: 'red_tilfoej_foraeldre_paastand', args: { p_barn_id: 50, p_family_id: 12 } });
  });
  it('foraeldrePaastand uden barn/familie → null', () => {
    expect(buildRpcCall({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: '50', payload: { barnId: 50 } } as never)).toBeNull();
  });
  it('vaelgForaeldre → red_vaelg_foraeldre(p_assertion_id, p_konfidens)', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50',
      payload: { assertionId: 88, konfidens: 'sikker' } })).toEqual({
      fn: 'red_vaelg_foraeldre', args: { p_assertion_id: 88, p_konfidens: 'sikker' } });
  });
  it('vaelgForaeldre uden konfidens → kun p_assertion_id', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50',
      payload: { assertionId: 88 } })).toEqual({ fn: 'red_vaelg_foraeldre', args: { p_assertion_id: 88 } });
  });
  it('vaelgForaeldre uden assertion → null', () => {
    expect(buildRpcCall({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: '50', payload: {} } as never)).toBeNull();
  });
});

describe('buildRpcCall — filside fase 1', () => {
  it('opdaterMedia sender kun de payload-felter der faktisk er til stede', () => {
    expect(buildRpcCall({ art: 'opdaterMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { titel: '', kunstner: 'Anna' } } as never)).toEqual({
      fn: 'red_opdater_media', args: { p_media_id: 91, p_titel: '', p_kunstner: 'Anna' },
    });
    expect(buildRpcCall({ art: 'opdaterMedia', subjektType: 'media', subjektId: '91' } as never)).toBeNull();
  });

  it('genopretMedia kræver mediaId', () => {
    expect(buildRpcCall({ art: 'genopretMedia', subjektType: 'media', subjektId: '91', mediaId: '91' } as never))
      .toEqual({ fn: 'red_genopret_media', args: { p_media_id: 91 } });
    expect(buildRpcCall({ art: 'genopretMedia', subjektType: 'media', subjektId: '91' } as never)).toBeNull();
  });

  it('mediaRettigheder sender gate + udfyldt dokumentation', () => {
    expect(buildRpcCall({ art: 'mediaRettigheder', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { status: 'licenseret', maaPubliceres: true, licens: 'CC BY 4.0', kildehenvisning: '' } } as never))
      .toEqual({ fn: 'red_set_media_rettigheder', args: {
        p_media_id: 91, p_status: 'licenseret', p_maa_publiceres: true, p_licens: 'CC BY 4.0',
      } });
  });

  it('uploadMedia fører kunstner/datering/status igennem', () => {
    const call = buildRpcCall({ art: 'uploadMedia', subjektType: 'person', subjektId: '42', payload: {
      afbildetPersonId: 42, slags: 'maleri', titel: 'Portræt', storagePath: 'x.jpg', mimeType: 'image/jpeg',
      kunstner: 'Jens Juel', datering: 'ca. 1780', rettighederStatus: 'public_domain',
    } } as never);
    expect(call?.args).toMatchObject({
      p_kunstner: 'Jens Juel', p_datering: 'ca. 1780', p_rettigheder_status: 'public_domain',
    });
  });

  it('nye domænefejl oversættes', () => {
    expect(oversaetFejl('Kan kun genoprette et fjernet medie')).toContain('kun genoprettes');
    expect(oversaetFejl('Slags kan ikke ryddes')).toBe('Slags kan ikke ryddes.');
  });
});

describe('buildRpcCall — tilknytMedia (mediehåndtering fase 2)', () => {
  it('person står på subjekt-siden', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } })).toEqual({
      fn: 'red_relation',
      args: {
        p_subjekt_type: 'person', p_subjekt_id: 42,
        p_objekt_type: 'media', p_objekt_id: 91,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it.each(['estate', 'coat_of_arms', 'lineage'] as const)('media står på subjekt-siden for %s', (maalType) => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType, maalId: '7' } })).toEqual({
      fn: 'red_relation',
      args: {
        p_subjekt_type: 'media', p_subjekt_id: 91,
        p_objekt_type: maalType, p_objekt_id: 7,
        p_rolle: 'afbildet', p_periode_raw: null,
      },
    });
  });

  it('afviser manglende eller ugyldige id-er og ukendt måltype', () => {
    const base = { art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } } as const;
    expect(buildRpcCall({ ...base, mediaId: undefined })).toBeNull();
    expect(buildRpcCall({ ...base, mediaId: '' })).toBeNull();
    expect(buildRpcCall({ ...base, mediaId: 'x' })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: 'x' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '0' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '-1' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { ...base.payload, maalId: '9223372036854775808' } })).toBeNull();
    expect(buildRpcCall({ ...base, payload: { maalType: 'organisation', maalId: '7' } })).toBeNull();
  });

  it('bevarer gyldige BIGINT-id-er over JavaScripts sikre heltalsgrænse som strenge', () => {
    expect(buildRpcCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91',
      mediaId: '9223372036854775807', payload: { maalType: 'person', maalId: '9007199254740992' } }))
      .toMatchObject({ args: { p_subjekt_id: '9007199254740992', p_objekt_id: '9223372036854775807' } });
  });

  it('kan degradere til red_suggest uden upload-gate', () => {
    const call = planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '42' } }, 'medlem');
    expect(call).toMatchObject({ fn: 'red_suggest', args: {
      p_art: 'tilknytMedia', p_payload: { maalType: 'person', maalId: '42', mediaId: '91' },
    } });
  });

  it('bevarer et stort media-id præcist i både staging-subjekt og payload', () => {
    const mediaId = '9223372036854775807';
    expect(planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: mediaId, mediaId,
      payload: { maalType: 'person', maalId: '42' } }, 'medlem')).toMatchObject({
      fn: 'red_suggest', args: { p_subjekt_id: mediaId, p_payload: { mediaId } },
    });
  });

  it('afviser en ugyldig tilknytning før staging', () => {
    expect(() => planCall({ art: 'tilknytMedia', subjektType: 'media', subjektId: '91', mediaId: '91',
      payload: { maalType: 'person', maalId: '0' } }, 'medlem')).toThrow('Ugyldig medietilknytning');
  });

  it('oversætter red_relation GDPR-guarden', () => {
    expect(oversaetFejl('afbildet skal gå person→media (person kan ikke stå på objekt-siden — GDPR-gating)'))
      .toBe('En person skal stå på subjekt-siden ved billedtilknytning.');
  });
});

describe('buildRpcCall — story/feed_pin (fase 3)', () => {
  it('opretStory → red_opret_story med payload-felter', () => {
    const change = { art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.', titel: 'Slaget', haendelseId: 91, dateRaw: '1671' } } as const;
    expect(buildRpcCall(change)).toEqual({ fn: 'red_opret_story', args: {
      p_subjekt_type: 'person', p_subjekt_id: 7, p_tekst: 'En minihistorie.',
      p_titel: 'Slaget', p_haendelse_id: 91, p_fact_id: null, p_relation_id: null,
      p_historical_event_id: null, p_date_min: null, p_date_max: null,
      p_date_qualifier: null, p_date_raw: '1671', p_privat: false,
    } });
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: '   ' } })).toBeNull();
    expect(planCall(change, 'medlem')).toMatchObject({ fn: 'red_suggest',
      args: { p_art: 'opretStory', p_payload: change.payload } });
  });

  it('redigerStory → red_rediger_story; kræver storyId + tekst', () => {
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.', privat: true } }))
      .toMatchObject({ fn: 'red_rediger_story',
        args: { p_story_id: 3, p_tekst: 'Omskrevet.', p_privat: true } });
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'x' } })).toBeNull();
    expect(planCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.' },
      kilder: [{ sourceId: 2, side: '112' }] }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { storyId: 3, tekst: 'Omskrevet.', kilder: [{ sourceId: 2, side: '112' }] },
      } });
  });

  it('opretStory-staging medtager de valgte kilder i det samlede forslag', () => {
    expect(planCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.' },
      kilder: [{ sourceId: 2 }, { sourceId: 5, side: '44' }] }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { tekst: 'En minihistorie.', kilder: [{ sourceId: 2 }, { sourceId: 5, side: '44' }] },
      } });
  });

  it('setStoryStatus validerer mod de fire koder', () => {
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'publiceret' }))
      .toEqual({ fn: 'red_set_story_status', args: { p_story_id: 3, p_status: 'publiceret' } });
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'udgivet' as never })).toBeNull();
  });

  it('sletStory / setStoryKilder / setFeedPin / fjernFeedPin', () => {
    expect(buildRpcCall({ art: 'sletStory', subjektType: 'person', subjektId: '7', storyId: 3 }))
      .toEqual({ fn: 'red_slet_story', args: { p_story_id: 3 } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3, kilder: [{ sourceId: 2, side: '112' }, { sourceId: 5 }] }))
      .toEqual({ fn: 'red_set_story_kilder', args: { p_story_id: 3,
        p_kilder: [{ source_id: 2, side: '112' }, { source_id: 5, side: null }] } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3 })).toBeNull();
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12', handling: 'pin' }))
      .toEqual({ fn: 'red_set_feed_pin', args: { p_kort_noegle: 'portrait:12', p_handling: 'pin' } });
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: '  ', handling: 'pin' })).toBeNull();
    expect(buildRpcCall({ art: 'fjernFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12' }))
      .toEqual({ fn: 'red_fjern_feed_pin', args: { p_kort_noegle: 'portrait:12' } });
    expect(planCall({ art: 'setFeedPin', subjektType: 'feed_pin', subjektId: '',
      kortNoegle: 'portrait:12', handling: 'skjul' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { kortNoegle: 'portrait:12', handling: 'skjul' },
      } });
    expect(planCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'klar' }, 'medlem'))
      .toMatchObject({ fn: 'red_suggest', args: {
        p_payload: { storyId: 3, storyStatus: 'klar' },
      } });
  });
});

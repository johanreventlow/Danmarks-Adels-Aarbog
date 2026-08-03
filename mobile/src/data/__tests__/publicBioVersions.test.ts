import { fetchPublicBioVersions } from '../publicBioVersions';

describe('fetchPublicBioVersions', () => {
  it('bevarer hver record fra samme bog og filtrerer private ekstrakolonner', async () => {
    const sb = { rpc: jest.fn().mockResolvedValue({ data: [
      { record_ref: 'r2', source_label: 'DAA 1939', record_label: 'Linje I, nr. 2', narrative_text: 'Anden', citation_label: 's. 2', provenance_kind: 'source_record', source_record_id: 'privat' },
      { record_ref: 'r1', source_label: 'DAA 1939', record_label: 'Linje I, nr. 1', narrative_text: 'Første', citation_label: 's. 1', provenance_kind: 'source_record' },
    ], error: null }) };
    const versions = await fetchPublicBioVersions(sb as never, ['1']);
    expect(versions.map((v) => v.recordRef)).toEqual(['r1', 'r2']);
    expect(versions[0]).not.toHaveProperty('sourceRecordId');
  });

  it('fejl eller manglende RPC giver null, så skærmen beholder sin eksisterende bio', async () => {
    await expect(fetchPublicBioVersions({ rpc: jest.fn().mockResolvedValue({ data: null, error: { message: 'mangler' } }) } as never, ['1'])).resolves.toBeNull();
  });
});

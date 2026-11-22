import { fetchPublicBioVersions, fetchPublicBioVersionsForPerson } from '../publicBioVersions';

describe('fetchPublicBioVersions', () => {
  it('bruger v2-kontrakten, bevarer hver record og filtrerer private ekstrakolonner', async () => {
    const sb = { rpc: jest.fn()
      .mockResolvedValueOnce({ data: 2, error: null })
      .mockResolvedValueOnce({ data: [
        { person_id: 1, source_id: 1, source_year: 1939, record_order: 2, source_record_ref: 'r2', source_label: 'DAA 1939', record_label: 'Linje I, nr. 2', narrative_text: 'Anden', citation_label: 's. 2', provenance_kind: 'source_record', source_record_id: 'privat' },
        { person_id: 1, source_id: 1, source_year: 1939, record_order: 1, source_record_ref: 'r1', source_label: 'DAA 1939', record_label: 'Linje I, nr. 1', narrative_text: 'Første', citation_label: 's. 1', provenance_kind: 'source_record' },
      ], error: null }) };
    const versions = await fetchPublicBioVersions(sb as never, ['1']);
    expect(versions!.map((v) => v.recordRef)).toEqual(['r1', 'r2']);
    expect(versions![0]).not.toHaveProperty('sourceRecordId');
    expect(sb.rpc).toHaveBeenNthCalledWith(1, 'narrative_record_contract_version', {});
    expect(sb.rpc).toHaveBeenNthCalledWith(2, 'public_person_bio_source_versions_v2', { p_person_ids: [1] });
  });

  it('beholder v1-kontrakten før cutover', async () => {
    const rpc = jest.fn()
      .mockResolvedValueOnce({ data: 1, error: null })
      .mockResolvedValueOnce({ data: [], error: null });
    await fetchPublicBioVersions({ rpc } as never, ['1']);
    expect(rpc).toHaveBeenNthCalledWith(2, 'public_person_bio_source_versions', { p_person_ids: [1] });
  });

  it('v2-fejl giver null uden v1- eller direkte-narrativ fallback', async () => {
    const rpc = jest.fn()
      .mockResolvedValueOnce({ data: 2, error: null })
      .mockResolvedValueOnce({ data: null, error: { message: 'mangler' } });
    await expect(fetchPublicBioVersions({ rpc } as never, ['1'])).resolves.toBeNull();
    expect(rpc).toHaveBeenCalledTimes(2);
  });

  it('henter kildeversioner for både canonical og alle same_som-aliaser', async () => {
    const rpc = jest.fn()
      .mockResolvedValueOnce({ data: 1, error: null })
      .mockResolvedValueOnce({ data: [], error: null });
    await fetchPublicBioVersionsForPerson({ rpc } as never, '10', [
      { personId: '3', linje: 'III', nr: 3, nr_label: null },
      { personId: '10', linje: 'I', nr: 1, nr_label: null },
      { personId: '2', linje: 'II', nr: 2, nr_label: null },
    ]);
    expect(rpc).toHaveBeenNthCalledWith(2, 'public_person_bio_source_versions', { p_person_ids: [10, 2, 3] });
  });
});

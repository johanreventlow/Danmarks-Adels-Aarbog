// Forældrefamilie-slot (Problem 2): konkurrerende forældre-påstande for DENNE person. Mirrorer web
// ForaeldrePaastandeControl: kilde-badge + valgt-markering + "Vælg denne" → vaelgForaeldre; plus §6
// trin (a) — importér en samme_som-linket persons (anden udgaves) forældre som rival-påstand.
// Renderes kun når der er noget at vise (påstande ELLER importable rivaler).
import { useEffect, useState } from 'react';
import { Pressable, View } from 'react-native';
import { Body, BtnLabel, Mono } from '../Typography';
import { KonfidensVaelger } from './KonfidensVaelger';
import { fetchForaeldreSlot, fetchBarnFamilie, type ForaeldreSlot, type BarnFamilie, type SammeSomLink } from '../../data/redaktionRead';
import { type Change } from '../../data/redaktionWrite';
import { Border, Colors, Radius } from '../../theme/tokens';

export function ForaeldrePaastandePanel({ personId, onChange, sammeSom, reloadKey }: {
  personId: string; onChange: (c: Change) => void; sammeSom: SammeSomLink[]; reloadKey?: number;
}) {
  const [slot, setSlot] = useState<ForaeldreSlot | null | undefined>(undefined);
  const [egen, setEgen] = useState<BarnFamilie | null>(null); // personens EGEN fødselsfamilie + udgave
  const [rivaler, setRivaler] = useState<{ fraId: string; fam: BarnFamilie }[]>([]);
  const [konfidens, setKonfidens] = useState<string | null>('sikker');
  useEffect(() => {
    let alive = true; setSlot(undefined); setRivaler([]); setEgen(null);
    fetchForaeldreSlot(personId).then((s) => { if (alive) setSlot(s); }).catch(() => { if (alive) setSlot(null); });
    fetchBarnFamilie(personId).then((f) => { if (alive) setEgen(f); }).catch(() => {});
    // ekskludér reflexive self-links (samme_som dækker også within-udgave-dubletter)
    Promise.all(sammeSom.filter((l) => l.modpartId !== personId).map((l) => fetchBarnFamilie(l.modpartId).then((f) => f ? { fraId: l.modpartId, fam: f } : null)))
      .then((rs) => { if (alive) setRivaler(rs.filter((r): r is { fraId: string; fam: BarnFamilie } => r != null)); }).catch(() => {});
    return () => { alive = false; };
  }, [personId, reloadKey, sammeSom]);

  const kendteFams = new Set((slot?.paastande ?? []).map((p) => p.familyId));
  // Kun ægte tværudgave-rivaler (anden familie + anden KILDE, ikke allerede på slottet). Kræver at
  // personens egen fødselsfamilie er kendt (ellers kan tværudgave ikke verificeres → intet tilbydes).
  const importable = (egen && egen.sourceId != null) ? rivaler.filter((r) =>
    r.fam.familyId !== egen.familyId && !kendteFams.has(r.fam.familyId) && r.fam.sourceId != null && r.fam.sourceId !== egen.sourceId) : [];
  if ((!slot || slot.paastande.length === 0) && importable.length === 0) return null;
  const omstridt = slot?.status === 'omstridt' || (slot?.paastande.length ?? 0) > 1;
  const vaelg = (assertionId: number) =>
    onChange({ art: 'vaelgForaeldre', subjektType: 'person', subjektId: personId, payload: { assertionId, konfidens } });
  const importer = (fam: BarnFamilie) =>
    onChange({ art: 'foraeldrePaastand', subjektType: 'person', subjektId: personId,
      payload: { barnId: personId, familyId: fam.familyId, sourceId: fam.sourceId ?? undefined, citat: fam.udgave ? `Importeret fra ${fam.udgave} (samme_som)` : undefined } });

  return (
    <View style={{ marginTop: 12, borderWidth: 1, borderColor: omstridt ? Colors.bordeaux : Border.light,
      borderRadius: Radius.card, padding: 12, backgroundColor: omstridt ? Colors.bordeauxFillLight : Colors.paperCard }}>
      <Mono size={9} color={omstridt ? Colors.bordeaux : Colors.textMuted} style={{ letterSpacing: 1, marginBottom: 8 }}>
        {omstridt ? 'FORÆLDREFAMILIE · KONKURRERENDE PÅSTANDE' : 'FORÆLDREFAMILIE'}
      </Mono>
      {(slot?.paastande ?? []).map((pp) => (
        <View key={pp.assertionId} style={{ paddingTop: 8, marginTop: 8, borderTopWidth: 1, borderTopColor: Border.light }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Mono size={9} color={Colors.textMuted} style={{ backgroundColor: Colors.paperBg, borderRadius: 5, paddingHorizontal: 6, paddingVertical: 2 }}>{pp.udgave ?? 'redaktionel'}</Mono>
            <Body size={13} style={{ flex: 1 }}>
              {pp.foraeldre.map((f) => f.navn).join(' & ') || '(ukendt familie)'}
              {pp.valgt ? <Body size={13} color={Colors.bordeaux}>{'  ✓ valgt'}</Body> : null}
            </Body>
          </View>
          {pp.side ? <Mono size={10} color={Colors.textMuted2} style={{ marginTop: 2 }}>{pp.side}</Mono> : null}
          {pp.valgt ? null : (
            <Pressable onPress={() => vaelg(pp.assertionId)}
              style={{ alignSelf: 'flex-start', marginTop: 6, paddingVertical: 7, paddingHorizontal: 13, borderRadius: Radius.field, backgroundColor: Colors.bordeaux }}>
              <BtnLabel color="#fff">Vælg denne</BtnLabel>
            </Pressable>
          )}
        </View>
      ))}
      {importable.map((r) => (
        <View key={r.fraId} style={{ paddingTop: 8, marginTop: 8, borderTopWidth: 1, borderTopColor: Border.light }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Mono size={9} color={Colors.gold} style={{ backgroundColor: Colors.paperBg, borderRadius: 5, paddingHorizontal: 6, paddingVertical: 2 }}>{r.fam.udgave ?? 'anden udgave'}</Mono>
            <Body size={13} color={Colors.textMuted} style={{ flex: 1 }}>{r.fam.foraeldre.map((f) => f.navn).join(' & ') || '(ukendt familie)'}</Body>
          </View>
          <Pressable onPress={() => importer(r.fam)}
            style={{ alignSelf: 'flex-start', marginTop: 6, paddingVertical: 7, paddingHorizontal: 13, borderRadius: Radius.field, borderWidth: 1, borderColor: Colors.bordeaux }}>
            <BtnLabel color={Colors.bordeaux}>Importér som påstand</BtnLabel>
          </Pressable>
        </View>
      ))}
      {omstridt ? (
        <View style={{ marginTop: 10 }}>
          <Mono size={9} color={Colors.textMuted} style={{ marginBottom: 5 }}>TILLID VED VALG</Mono>
          <KonfidensVaelger vaerdi={konfidens} onVael={setKonfidens} />
        </View>
      ) : null}
    </View>
  );
}

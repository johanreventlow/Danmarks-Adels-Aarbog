// Ændringshistorik for en person (D1) — viser change_set-poster m. fortryd-knap +
// en samlet døde-links-rapport (D3). Redaktion-only API (hist_for_subjekt/red_doede_links).
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, ActivityIndicator, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { TopBar } from '../../../components/TopBar';
import { Body, BtnLabel, Mono, Serif } from '../../../components/Typography';
import { fetchHistorik, fetchDoedeLinks, type HistPost, type DoedLink } from '../../../data/redaktionRead';
import { submitChange, oversaetFejl } from '../../../data/redaktionWrite';
import { useStore } from '../../../store/useStore';
import { Border, Colors, Radius } from '../../../theme/tokens';

export default function HistorikSkaerm() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const dryRun = useStore((s) => s.dryRun);
  const [poster, setPoster] = useState<HistPost[]>([]);
  const [doede, setDoede] = useState<DoedLink[]>([]);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [fejl, setFejl] = useState<string | null>(null);

  const indlæs = useCallback(async () => {
    try {
      setStatus('loading');
      const [hist, dl] = await Promise.all([fetchHistorik(String(id)), fetchDoedeLinks()]);
      setPoster(hist);
      setDoede(dl);
      setStatus('ready');
    } catch (e: any) {
      setFejl(oversaetFejl(e.message));
      setStatus('error');
    }
  }, [id]);
  useEffect(() => { indlæs(); }, [indlæs]);

  const fortryd = useCallback(async (post: HistPost, force: boolean) => {
    try {
      await submitChange({
        art: 'fortryd', subjektType: 'person', subjektId: String(id),
        payload: { changeSetId: Number(post.id), force },
      }, { dryRun });
      await indlæs();
    } catch (e: any) {
      const msg = e.message as string;
      // Beskeds-match holdes i sync med DB-RAISE'en i red_fortryd_change_set (spec-B9).
      if (/afvist.*force/i.test(msg) && !force) {
        Alert.alert('Nyere ændring rører samme data', 'Fortryd alligevel?', [
          { text: 'Annullér', style: 'cancel' },
          { text: 'Fortryd alligevel', style: 'destructive', onPress: () => fortryd(post, true) },
        ]);
      } else {
        Alert.alert('Fejl', oversaetFejl(msg));
      }
    }
  }, [id, dryRun, indlæs]);

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Ændringshistorik" />
      {status === 'loading' ? <ActivityIndicator style={{ marginTop: 40 }} /> : null}
      {status === 'error' ? <Body color={Colors.danger} style={{ padding: 16 }}>{fejl}</Body> : null}
      {status === 'ready' ? (
        <ScrollView contentContainerStyle={{ paddingBottom: 28 }}>
          {poster.length === 0 ? (
            <Body color={Colors.textMuted} style={{ padding: 16 }}>Ingen ændringer registreret.</Body>
          ) : null}
          {poster.map((post) => (
            <View key={post.id} style={[styles.kort, post.reverteret && styles.kortReverteret]}>
              <Body size={14}>{post.resume}</Body>
              <Mono size={11} color={Colors.textMuted} style={{ marginTop: 4 }}>
                {post.hvem} · {post.hvornaar}
              </Mono>
              {!post.reverteret ? (
                <Pressable style={styles.fortrydKnap} onPress={() => fortryd(post, false)}>
                  <BtnLabel color={Colors.danger}>Fortryd</BtnLabel>
                </Pressable>
              ) : (
                <Mono size={10} color={Colors.textMuted} style={{ marginTop: 8 }}>Fortrudt</Mono>
              )}
            </View>
          ))}

          <View style={styles.doedeSektion}>
            <Serif size={18} style={{ marginBottom: 8 }}>Døde links ({doede.length})</Serif>
            {doede.length === 0 ? (
              <Body size={13} color={Colors.textMuted}>Ingen.</Body>
            ) : (
              doede.map((d, i) => (
                <Mono key={i} size={11} color={Colors.textMuted} style={{ marginBottom: 4 }}>
                  {d.kilde} → {d.maalType}:{d.maalId}
                </Mono>
              ))
            )}
          </View>
        </ScrollView>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  kort: {
    backgroundColor: Colors.paperCard,
    marginHorizontal: 16,
    marginTop: 12,
    padding: 12,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Border.light,
  },
  kortReverteret: { opacity: 0.55 },
  fortrydKnap: { alignSelf: 'flex-start', marginTop: 8 },
  doedeSektion: { padding: 16, marginTop: 12, borderTopWidth: 1, borderTopColor: Border.light },
});

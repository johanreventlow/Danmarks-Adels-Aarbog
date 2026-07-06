// Bogmærker-skærm (konto-bogmærker, spec 2026-07-06). Login-eksklusivt: udlogget viser tom-
// tilstand med login-CTA i stedet for en liste.
import { useRouter } from 'expo-router';
import { useMemo } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../components/InitialBadge';
import { LoadGate } from '../components/LoadGate';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { useBookmarks } from '../lib/bookmarks';
import { useStore } from '../store/useStore';
import { Border, Colors } from '../theme/tokens';

export default function BogmaerkerScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const canonMap = useStore((s) => s.canonicalIdById);
  const session = useStore((s) => s.session);
  const { ids, canSave } = useBookmarks(session?.user?.id ?? null, canonMap);

  const people = useMemo(
    () => (model ? [...ids].map((id) => model.byId[id]).filter(Boolean) : []),
    [ids, model],
  );

  return (
    <LoadGate>
      <ScrollView
        style={{ flex: 1, backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top + 12, paddingHorizontal: 18, paddingBottom: 30 }}>
        {!canSave ? (
          <View style={{ marginTop: 24 }}>
            <Body size={13} color={Colors.textSecondary2}>
              Log ind for at samle dine bogmærker på tværs af dine enheder.
            </Body>
            <Pressable onPress={() => router.push('/konto')} style={{ marginTop: 12 }}>
              <BtnLabel size={13} color={Colors.bordeaux}>Log ind ›</BtnLabel>
            </Pressable>
          </View>
        ) : people.length === 0 ? (
          <Body size={13} color={Colors.textSecondary2} style={{ marginTop: 24 }}>
            Du har endnu ikke gemt nogen blade. Tryk bogmærke-ikonet på et kort i feedet.
          </Body>
        ) : (
          <>
            <Body size={13} color={Colors.textSecondary2} style={{ marginBottom: 14 }}>
              Blade du har gemt fra feedet.
            </Body>
            {people.map((p) => (
              <Pressable
                key={p.id}
                onPress={() => router.push(`/person/${p.id}`)}
                style={{
                  flexDirection: 'row', alignItems: 'center', gap: 13, paddingVertical: 12,
                  borderBottomWidth: 1, borderBottomColor: Border.faint,
                }}>
                <InitialBadge name={p.name} size={42} bg={Colors.beige2} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Serif size={18} style={{ lineHeight: 19 }}>{p.name}</Serif>
                  {p.years ? <Body size={11.5} color={Colors.textSecondary2}>{p.years}</Body> : null}
                </View>
                <Serif size={18} color="#bcae93">›</Serif>
              </Pressable>
            ))}
          </>
        )}
      </ScrollView>
    </LoadGate>
  );
}

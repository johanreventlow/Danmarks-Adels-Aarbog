// Indlæsnings-gate: viser spinner mens data hentes, og en diskret banner hvis appen kører
// på offline-seed (live-hentning fejlede). Wrapper skærm-indhold.
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { useStore } from '../store/useStore';
import { Colors } from '../theme/tokens';
import { Kicker } from './Typography';

export function LoadGate({ children }: { children: React.ReactNode }) {
  const status = useStore((s) => s.status);
  const source = useStore((s) => s.source);
  const error = useStore((s) => s.error);

  if (status === 'loading' || status === 'idle') {
    return (
      <View style={styles.center}>
        <ActivityIndicator color={Colors.bordeaux} />
        <Kicker style={{ marginTop: 12 }}>Henter slægtsdata…</Kicker>
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      {source === 'seed' ? (
        <View style={styles.banner}>
          <Kicker color={Colors.bordeaux} size={9}>
            Offline-visning · begrænset seed-data
          </Kicker>
          {/* Fejlteksten vises, fordi et Release-build ingen konsol har: uden den er næste fejl blind. */}
          {error ? (
            <Kicker color={Colors.bordeaux} size={8} style={{ marginTop: 2, textTransform: 'none' }} numberOfLines={2}>
              {error}
            </Kicker>
          ) : null}
        </View>
      ) : null}
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: Colors.surfaceGround },
  banner: {
    backgroundColor: Colors.bordeauxTint,
    paddingVertical: 5,
    alignItems: 'center',
  },
});

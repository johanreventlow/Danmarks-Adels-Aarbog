import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import type { TidslinjePost } from '../../data/redaktionRead';
import { Border, Colors, Radius } from '../../theme/tokens';
import { BtnLabel, Mono, Serif } from '../Typography';
import { personEditorSheetStyles } from './personEditorSheetStyles';

type Status = 'kandidat' | 'interessant' | 'skjult';
const STATUS: Status[] = ['kandidat', 'interessant', 'skjult'];

function datoLabel(p: TidslinjePost) {
  if (p.dato.raw) return p.dato.raw;
  if (p.dato.min && p.dato.max && p.dato.min !== p.dato.max) return `${p.dato.min} – ${p.dato.max}`;
  return p.dato.min ?? p.dato.max ?? 'udateret';
}

export function HaendelseTidslinje({ poster, onSetStatus }: {
  poster: TidslinjePost[];
  onSetStatus: (haendelseId: number, status: Status) => void;
}) {
  const [open, setOpen] = useState(true);
  return (
    <View style={styles.section}>
      <Pressable style={styles.header} onPress={() => setOpen((v) => !v)}>
        <Mono size={10} color={Colors.gold}>HÆNDELSER · TIDSLINJE FRA PROSAEN</Mono>
        <Mono size={9} color={Colors.textMuted}>{poster.length} · {open ? 'skjul' : 'vis'}</Mono>
      </Pressable>
      {open ? poster.map((p) => (
        <View key={p.id} style={styles.card}>
          <View style={styles.meta}>
            <Mono size={9} color={Colors.bordeaux}>{datoLabel(p)}</Mono>
            <Mono size={8} color={Colors.textMuted}>{p.art === 'rygrad' ? 'RYGRAD' : (p.kategori ?? 'ANDET').toUpperCase()}</Mono>
          </View>
          <Serif size={16}>“{p.klausul}”</Serif>
          <Mono size={8} color={Colors.textMuted} style={{ marginTop: 5 }}>
            {[p.sourceTitel, p.side ? `s. ${p.side}` : null].filter(Boolean).join(', ') || 'kilde mangler'}
          </Mono>
          {p.art === 'haendelse' && p.haendelseId != null ? (
            <View style={styles.statusRow}>
              {STATUS.map((status) => {
                const aktiv = p.feedStatus === status;
                return <Pressable key={status}
                  style={[personEditorSheetStyles.koenPille, aktiv && personEditorSheetStyles.koenPilleAktiv]}
                  onPress={() => onSetStatus(p.haendelseId as number, status)}>
                  <BtnLabel size={10} color={aktiv ? '#fff' : Colors.textSecondary2}>{status}</BtnLabel>
                </Pressable>;
              })}
            </View>
          ) : null}
        </View>
      )) : null}
      {open && !poster.length ? <Mono size={9} color={Colors.textMuted}>Ingen daterede poster endnu.</Mono> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  section: { marginTop: 14, marginBottom: 12 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  card: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.card, padding: 12, marginBottom: 8 },
  meta: { flexDirection: 'row', justifyContent: 'space-between', gap: 8, marginBottom: 6 },
  statusRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 10 },
});

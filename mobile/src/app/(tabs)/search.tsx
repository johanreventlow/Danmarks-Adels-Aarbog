// Søg / bladr (README §5.5 + §9.1 alfabet-hop). Søgefelt + alfabet-chips (kun forekommende
// bogstaver, dansk orden, Æ/Ø/Å sidst) + sticky bogstav-headers via SectionList + sortér-toggle
// alfabetisk/fødeår. Alfabet-baren skjules ved fødeår-sort og når der søges.
import { useRouter } from 'expo-router';
import { useMemo } from 'react';
import {
  Pressable,
  SectionList,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../../components/InitialBadge';
import { LoadGate } from '../../components/LoadGate';
import { Body, BtnLabel, Mono, Serif } from '../../components/Typography';
import { buildSearch, type SearchItem } from '../../data/selectors';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';

export default function SearchScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const query = useStore((s) => s.query);
  const setQuery = useStore((s) => s.setQuery);
  const sort = useStore((s) => s.browseSort);
  const setSort = useStore((s) => s.setBrowseSort);
  const activeLetter = useStore((s) => s.activeLetter);
  const setActiveLetter = useStore((s) => s.setActiveLetter);

  const { matches, letters, showLetters, groups } = useMemo(
    () => buildSearch(model, { query, sort, activeLetter }),
    [model, query, sort, activeLetter],
  );

  // SectionList-data: grupperet (alfabetisk, ingen query) ELLER én flad sektion.
  const sections = useMemo(() => {
    if (groups.length) return groups.map((g) => ({ title: g.letter, data: g.people }));
    return [{ title: '', data: matches }];
  }, [groups, matches]);

  return (
    <LoadGate>
      <View style={{ flex: 1, paddingTop: insets.top + 8 }}>
        <View style={styles.header}>
          <TextInput
            style={styles.input}
            placeholder="Søg navn…"
            placeholderTextColor={Colors.textMuted}
            value={query}
            onChangeText={setQuery}
            autoCorrect={false}
          />
          {/* Sortér-toggle (segmenteret, jf. design) */}
          <View style={styles.sortRow}>
            <SortPill label="A–Å" active={sort === 'alpha'} onPress={() => setSort('alpha')} />
            <SortPill label="Født" active={sort === 'born'} onPress={() => setSort('born')} />
          </View>

          {/* Alfabet-chips (§9.1) */}
          {showLetters ? (
            <View style={styles.letterRow}>
              {letters.map((l) => {
                const active = (l.key ?? null) === (activeLetter ?? null);
                return (
                  <Pressable
                    key={l.label}
                    onPress={() => setActiveLetter(l.key)}
                    style={[styles.letterChip, active && styles.letterChipActive]}>
                    <Mono
                      size={10}
                      color={active ? Colors.paperBg : Colors.textSecondary2}
                      style={{ letterSpacing: 0 }}>
                      {l.label}
                    </Mono>
                  </Pressable>
                );
              })}
            </View>
          ) : null}
        </View>

        <SectionList
          sections={sections}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled
          keyboardShouldPersistTaps="handled"
          contentContainerStyle={{ paddingBottom: insets.bottom + 80 }}
          renderSectionHeader={({ section }) =>
            section.title ? (
              <View style={styles.sectionHeader}>
                <Serif size={15} color={Colors.gold}>{section.title}</Serif>
              </View>
            ) : null
          }
          renderItem={({ item }) => (
            <PersonRow item={item} onPress={() => router.push(`/person/${item.id}`)} />
          )}
          ListEmptyComponent={
            <View style={{ padding: 24, alignItems: 'center' }}>
              <Body color={Colors.textMuted}>Ingen personer fundet.</Body>
            </View>
          }
        />
      </View>
    </LoadGate>
  );
}

function SortPill({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.sortPill, active && styles.sortPillActive]}>
      <BtnLabel size={11} color={active ? Colors.paperBg : Colors.textSecondary2}>{label}</BtnLabel>
    </Pressable>
  );
}

function PersonRow({ item, onPress }: { item: SearchItem; onPress: () => void }) {
  return (
    <Pressable style={styles.row} onPress={onPress}>
      <InitialBadge name={item.name} size={40} bg={Colors.beige2} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <Serif size={18} style={{ lineHeight: 19 }}>{item.name}</Serif>
        {item.years ? <Mono size={10} color={Colors.textMuted}>{item.years}</Mono> : null}
      </View>
      <Serif size={18} color="#bcae93">›</Serif>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 18, paddingTop: 14, paddingBottom: 8 },
  input: {
    backgroundColor: Colors.paperCard,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 15,
    paddingVertical: 13,
    fontFamily: Fonts.sans,
    fontSize: 15,
    color: Colors.ink,
  },
  sortRow: { flexDirection: 'row', gap: 8, marginTop: 10 },
  sortPill: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: Radius.chip,
    backgroundColor: Colors.beige,
  },
  sortPillActive: { backgroundColor: Colors.bordeaux },
  letterRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 3, marginTop: 12 },
  letterChip: {
    minWidth: 19,
    paddingHorizontal: 5,
    paddingVertical: 3,
    borderRadius: Radius.badge,
    alignItems: 'center',
    backgroundColor: 'transparent',
  },
  letterChipActive: { backgroundColor: Colors.bordeaux },
  sectionHeader: {
    backgroundColor: Colors.paperBg,
    paddingHorizontal: 18,
    paddingTop: 7,
    paddingBottom: 3,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(34,31,26,0.07)',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    paddingVertical: 11,
    paddingHorizontal: 18,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.faint,
  },
});

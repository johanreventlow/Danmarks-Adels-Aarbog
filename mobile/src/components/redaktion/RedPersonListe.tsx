import { useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, SectionList, StyleSheet, TextInput, View } from 'react-native';
import { InitialBadge } from '../InitialBadge';
import { TopBar } from '../TopBar';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import { fetchRedaktionPersoner, type RedPerson } from '../../data/redaktionRead';
import { searchPool, type SearchItem } from '../../data/selectors';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

export function RedPersonListe() {
  const router = useRouter();
  const session = useStore((s) => s.session);
  const [personer, setPersoner] = useState<RedPerson[]>([]);
  const [fejl, setFejl] = useState(false);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<'alpha' | 'born'>('alpha');
  const [activeLetter, setActiveLetter] = useState<string | null>(null);

  useEffect(() => {
    setFejl(false);
    // Fejl vises eksplicit, ALDRIG som tom liste (cycle 03 NEW1).
    fetchRedaktionPersoner().then(setPersoner).catch(() => setFejl(true));
  }, [session]);

  // RedPerson → SearchItem-pool; tags slås op separat (holder SearchItem ren).
  const pool = useMemo<SearchItem[]>(
    () => personer.map((p) => ({ id: p.id, name: p.navn, years: p.aar, born: p.born })),
    [personer],
  );
  const skjult = useMemo(() => {
    const m = new Map<string, 'levende' | 'privat'>();
    personer.forEach((p) => { if (p.privat) m.set(p.id, 'privat'); else if (p.levende) m.set(p.id, 'levende'); });
    return m;
  }, [personer]);

  const { matches, letters, showLetters, groups } = useMemo(
    () => searchPool(pool, { query, sort, activeLetter }),
    [pool, query, sort, activeLetter],
  );
  const sections = useMemo(() => {
    if (groups.length) return groups.map((g) => ({ title: g.letter, data: g.people }));
    return [{ title: '', data: matches }];
  }, [groups, matches]);

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Personer" showBack={false} />
      <View style={styles.header}>
        <TextInput style={styles.input} placeholder="Søg navn…" placeholderTextColor={Colors.textMuted}
          value={query} onChangeText={setQuery} autoCorrect={false} />
        <View style={styles.sortRow}>
          <SortPill label="A–Å" active={sort === 'alpha'} onPress={() => setSort('alpha')} />
          <SortPill label="Født" active={sort === 'born'} onPress={() => setSort('born')} />
        </View>
        {showLetters ? (
          <View style={styles.letterRow}>
            {letters.map((l) => {
              const active = (l.key ?? null) === (activeLetter ?? null);
              return (
                <Pressable key={l.label} onPress={() => setActiveLetter(l.key)}
                  style={[styles.letterChip, active && styles.letterChipActive]}>
                  <Mono size={10} color={active ? Colors.paperBg : Colors.textSecondary2}>{l.label}</Mono>
                </Pressable>
              );
            })}
          </View>
        ) : null}
      </View>

      {fejl ? (
        <View style={{ padding: 24 }}>
          <Mono size={11} color={Colors.liveRoed}>Kunne ikke hente personer. Tom liste her betyder IKKE "ingen personer".</Mono>
        </View>
      ) : (
        <SectionList
          style={{ flex: 1 }}
          sections={sections}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled
          keyboardShouldPersistTaps="handled"
          renderSectionHeader={({ section }) =>
            section.title ? (
              <View style={styles.sectionHeader}><Serif size={15} color={Colors.gold}>{section.title}</Serif></View>
            ) : null
          }
          renderItem={({ item }) => (
            <PersonRow item={item} tag={skjult.get(item.id)} onPress={() => router.push(`/redaktion/person/${item.id}` as never)} />
          )}
          ListEmptyComponent={<View style={{ padding: 24 }}><Body color={Colors.textMuted}>Ingen personer.</Body></View>}
        />
      )}
    </View>
  );
}

function SortPill({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.sortPill, active && styles.sortPillActive]}>
      <BtnLabel size={11} color={active ? Colors.paperBg : Colors.textSecondary2}>{label}</BtnLabel>
    </Pressable>
  );
}

function PersonRow({ item, tag, onPress }: { item: SearchItem; tag?: 'levende' | 'privat'; onPress: () => void }) {
  return (
    <Pressable style={styles.row} onPress={onPress}>
      <InitialBadge name={item.name} size={40} bg={Colors.beige2} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <Serif size={18} style={{ lineHeight: 19 }}>{item.name}</Serif>
        {item.years ? <Mono size={10} color={Colors.textMuted}>{item.years}</Mono> : null}
      </View>
      {tag ? (
        <View style={styles.tag}><Mono size={8} color={Colors.bordeaux}>{tag.toUpperCase()}</Mono></View>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 16, paddingTop: 8, paddingBottom: 6, gap: 8 },
  input: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: Radius.field, paddingHorizontal: 12, paddingVertical: 9, fontFamily: 'HankenGrotesk_400Regular', fontSize: 14 },
  sortRow: { flexDirection: 'row', gap: 8 },
  sortPill: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 14, paddingVertical: 5 },
  sortPillActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  letterRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 5 },
  letterChip: { paddingHorizontal: 7, paddingVertical: 3, borderRadius: Radius.badge, backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light },
  letterChipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  sectionHeader: { backgroundColor: Colors.paperBg, paddingHorizontal: 16, paddingVertical: 4 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 16, paddingVertical: 9 },
  tag: { backgroundColor: Colors.bordeauxFillLight, borderRadius: Radius.badge, paddingHorizontal: 6, paddingVertical: 3 },
});

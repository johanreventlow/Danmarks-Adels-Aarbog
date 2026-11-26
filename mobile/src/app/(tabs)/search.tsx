// Søg / bladr (README §5.5 + §9.1 alfabet-hop). Uden søgeord og afgrænsning: bladring med alfabet-chips (kun
// forekommende bogstaver, dansk orden, Æ/Ø/Å sidst), sticky bogstav-headers og sortér-toggle alfabetisk/fødeår.
// Med søgeord eller afgrænsning: web's søgning fra @daa/core (soeg — personer OG besiddelser, andre stavemåder som
// Detlef/Detlev og Reventlov/Reventlow, linje- og levetidsfilter, »Andre stavemåder«/»Mente du …?«).
import {
  byggStaveordbog, soeg, stavemaader, synligeLinjer, STANDARD_FILTRE,
  type GodsRaekke, type Maerke, type PersonRaekke, type SoegFiltre, type SoegType,
} from '@daa/core';
import { useRouter } from 'expo-router';
import { useDeferredValue, useMemo, useState } from 'react';
import {
  FlatList,
  Pressable,
  SectionList,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { InitialBadge } from '../../components/InitialBadge';
import { LoadGate } from '../../components/LoadGate';
import { Body, BtnLabel, Mono, Serif } from '../../components/Typography';
import { besiddelserVist, ejerTekst } from '../../data/besiddelser';
import { buildSearch, type SearchItem } from '../../data/selectors';
import {
  aarFraTekst, antalAfgraensninger, fremhaevDele, ingenTitel, soegerAktivt, statusTekst, visGodser, visPersoner,
} from '../../data/soegning';
import { useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';

type Raekke =
  | { kind: 'overskrift'; id: string; tekst: string }
  | { kind: 'person'; id: string; p: PersonRaekke }
  | { kind: 'gods'; id: string; g: GodsRaekke };

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

  const aux = useStore((s) => s.aux);
  // Søgningens egne valg (web har dem i adressen; mobilen holder dem på skærmen). Søgeordet ligger i storen som før.
  const [bedst, setBedst] = useState(true);
  const [type, setType] = useState<SoegType>('alt');
  const [linje, setLinje] = useState<string | null>(null);
  const [fra, setFra] = useState<number | null>(null);
  const [til, setTil] = useState<number | null>(null);
  const [visAfgraens, setVisAfgraens] = useState(false);

  const f: SoegFiltre = {
    ...STANDARD_FILTRE, q: query, type, linje, fra, til,
    sort: query.trim() && bedst ? 'match' : sort === 'born' ? 'foedt' : 'navn',
  };
  const aktiv = soegerAktivt(f);
  const linjer = useMemo(() => synligeLinjer(model?.lineage?.list ?? []), [model]);
  const estates = useMemo(() => besiddelserVist(aux?.estateList ?? [], model), [aux, model]);

  const { matches, letters, showLetters, groups } = useMemo(
    () => buildSearch(model, { query: aktiv ? '' : query, sort, activeLetter }),
    [model, query, sort, activeLetter, aktiv],
  );
  const res = useMemo(
    () => (model && aktiv ? soeg(model, estates, f) : null),
    // f er afledt af de enkelte felter herunder.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [model, estates, aktiv, query, type, linje, fra, til, f.sort],
  );
  // Andre stavemåder (Reventlow ↔ Reventlou) med antal træffere under samme afgrænsning; kun dem, der finder noget.
  // Ordbogen bygges én gang pr. model, forslagene regnes på et udskudt søgeord (som web, review 37 Y7).
  const ordbog = useMemo(
    () => (model ? byggStaveordbog([...model.persons.map((p) => p.name), ...estates.map((e) => e.navn)]) : null),
    [model, estates],
  );
  const qUdskudt = useDeferredValue(query);
  const andre = useMemo(() => {
    if (!model || !ordbog || !aktiv || !qUdskudt.trim()) return [];
    return stavemaader(ordbog, qUdskudt)
      .map((q) => { const r = soeg(model, estates, { ...f, q }); return { q, n: r.personer.length + r.godser.length }; })
      .filter((x) => x.n > 0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model, ordbog, estates, aktiv, qUdskudt, type, linje, fra, til]);

  // SectionList-data: grupperet (alfabetisk, ingen query) ELLER én flad sektion.
  const sections = useMemo(() => {
    if (groups.length) return groups.map((g) => ({ title: g.letter, data: g.people }));
    return [{ title: '', data: matches }];
  }, [groups, matches]);

  const raekker = useMemo((): Raekke[] => {
    if (!res) return [];
    const ud: Raekke[] = [];
    const medGodser = visGodser(f, res);
    if (visPersoner(f) && res.personer.length) {
      if (medGodser) ud.push({ kind: 'overskrift', id: 'h-personer', tekst: 'Personer' });
      res.personer.forEach((p) => ud.push({ kind: 'person', id: `p-${p.id}`, p }));
    }
    if (medGodser) {
      if (f.type === 'alt' && res.personer.length) ud.push({ kind: 'overskrift', id: 'h-godser', tekst: 'Besiddelser' });
      res.godser.forEach((g) => ud.push({ kind: 'gods', id: `g-${g.id}`, g }));
    }
    return ud;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [res, type]);

  const antal = antalAfgraensninger(f);
  const nulstil = () => { setType('alt'); setLinje(null); setFra(null); setTil(null); };

  return (
    <LoadGate>
      <View style={{ flex: 1, paddingTop: insets.top + 8 }}>
        <View style={styles.header}>
          <TextInput
            style={styles.input}
            placeholder="Søg efter en person eller en besiddelse"
            placeholderTextColor={Colors.inkMuted}
            value={query}
            onChangeText={setQuery}
            autoCorrect={false}
          />
          {/* Sortér-toggle (segmenteret, jf. design); »Bedst« kun med et søgeord, som web's »bedste match«. */}
          <View style={styles.sortRow}>
            {query.trim() ? <SortPill label="Bedst" active={bedst} onPress={() => setBedst(true)} /> : null}
            <SortPill label="A–Å" active={!(query.trim() && bedst) && sort === 'alpha'} onPress={() => { setBedst(false); setSort('alpha'); }} />
            <SortPill label="Født" active={!(query.trim() && bedst) && sort === 'born'} onPress={() => { setBedst(false); setSort('born'); }} />
            <View style={{ flex: 1 }} />
            <Pressable onPress={() => setVisAfgraens((v) => !v)} accessibilityRole="button" accessibilityState={{ expanded: visAfgraens }} hitSlop={6}>
              <BtnLabel size={12} color={Colors.bordeaux}>Afgræns{antal ? ` (${antal} valgt)` : ''} {visAfgraens ? '▴' : '▾'}</BtnLabel>
            </Pressable>
          </View>

          {visAfgraens ? (
            <Afgraens f={f} res={res} linjer={linjer} onType={setType} onLinje={setLinje} onFra={setFra} onTil={setTil}
              onNulstil={antal ? nulstil : null} />
          ) : null}

          {/* Alfabet-chips (§9.1) */}
          {!aktiv && showLetters ? (
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
                      color={active ? Colors.inkOnInverse : Colors.inkMuted}
                      style={{ letterSpacing: 0 }}>
                      {l.label}
                    </Mono>
                  </Pressable>
                );
              })}
            </View>
          ) : null}
        </View>

        {aktiv && res ? (
          <FlatList
            style={{ flex: 1 }}
            data={raekker}
            keyExtractor={(r) => r.id}
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{ paddingBottom: insets.bottom + 80 }}
            ListHeaderComponent={
              <View style={{ paddingHorizontal: 18, paddingBottom: 6 }}>
                <Body size={12.5} color={Colors.inkMuted} accessibilityLiveRegion="polite">{statusTekst(f, res)}</Body>
                {andre.length > 0 && raekker.length > 0 ? (
                  <Body size={13} color={Colors.inkSecondary} style={{ marginTop: 4 }}>
                    Andre stavemåder:{' '}
                    {andre.map((x, i) => (
                      <Text key={x.q}>
                        {i > 0 ? ' · ' : ''}
                        <Text style={styles.stavLink} onPress={() => setQuery(x.q)} accessibilityRole="link">{x.q} ({x.n})</Text>
                      </Text>
                    ))}
                  </Body>
                ) : null}
              </View>
            }
            renderItem={({ item }) =>
              item.kind === 'overskrift' ? (
                <View style={styles.sectionHeader}>
                  <Mono size={10} color={Colors.inkMuted} style={{ letterSpacing: 10 * 0.16, textTransform: 'uppercase' }}>{item.tekst}</Mono>
                </View>
              ) : item.kind === 'person' ? (
                <Pressable style={styles.row} onPress={() => router.push(`/person/${item.p.id}`)} accessibilityRole="link">
                  <InitialBadge name={item.p.name} size={40} bg={Colors.surfaceSunken} />
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Serif size={18} style={{ lineHeight: 19 }}><Fremhaev tekst={item.p.name} maerker={item.p.maerker} /></Serif>
                    {item.p.years || item.p.title ? (
                      <Mono size={10} color={Colors.inkMuted}>{[item.p.years, item.p.title].filter(Boolean).join(' · ')}</Mono>
                    ) : null}
                    {item.p.linje ? <Mono size={9.5} color={Colors.inkSecondary} style={{ marginTop: 1 }}>{item.p.linje}</Mono> : null}
                  </View>
                  <Serif size={18} color="#bcae93">›</Serif>
                </Pressable>
              ) : (
                <Pressable style={styles.row} onPress={() => router.push(`/estate/${item.g.id}`)} accessibilityRole="link">
                  <View style={styles.crest}><Serif size={16} color={Colors.bordeaux}>⌂</Serif></View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Serif size={18} style={{ lineHeight: 19 }}><Fremhaev tekst={item.g.navn} maerker={item.g.maerker} /></Serif>
                    <Mono size={10} color={Colors.inkMuted}>{ejerTekst(item.g.ejere)}</Mono>
                  </View>
                  <Serif size={18} color="#bcae93">›</Serif>
                </Pressable>
              )
            }
            ListEmptyComponent={
              <View style={{ padding: 24 }}>
                <Serif size={20}>{ingenTitel(f)}</Serif>
                {andre.length > 0 ? (
                  <Body size={13.5} color={Colors.inkSecondary} style={{ marginTop: 6 }}>
                    Mente du{' '}
                    {andre.map((x, i) => (
                      <Text key={x.q}>
                        {i > 0 ? (i === andre.length - 1 ? ' eller ' : ', ') : ''}
                        <Text style={styles.stavLink} onPress={() => setQuery(x.q)} accessibilityRole="link">{x.q}</Text>
                      </Text>
                    ))}
                    ? Stavemåder skifter gennem udgaverne.
                  </Body>
                ) : (
                  <Body size={13.5} color={Colors.inkSecondary} style={{ marginTop: 6 }}>
                    {f.q.trim() ? 'Prøv en anden stavemåde. Stavemåder skifter gennem udgaverne.' : 'Prøv at fjerne en afgrænsning.'}
                  </Body>
                )}
              </View>
            }
          />
        ) : (
          <SectionList
            style={{ flex: 1 }}
            sections={sections}
            keyExtractor={(item) => item.id}
            stickySectionHeadersEnabled
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{ paddingBottom: insets.bottom + 80 }}
            renderSectionHeader={({ section }) =>
              section.title ? (
                <View style={styles.sectionHeader}>
                  <Serif size={15} color={Colors.goldInk}>{section.title}</Serif>
                </View>
              ) : null
            }
            renderItem={({ item }) => (
              <PersonRow item={item} onPress={() => router.push(`/person/${item.id}`)} />
            )}
            ListEmptyComponent={
              <View style={{ padding: 24, alignItems: 'center' }}>
                <Body color={Colors.inkMuted}>Ingen personer fundet.</Body>
              </View>
            }
          />
        )}
      </View>
    </LoadGate>
  );
}

// Navnet med de bogstavret genfundne søgeord fremhævet (web's Fremhaev); et foldet match vises uden fremhævning.
function Fremhaev({ tekst, maerker }: { tekst: string; maerker: Maerke[] }) {
  return (
    <>
      {fremhaevDele(tekst, maerker).map((d, i) => (
        <Text key={i} style={d.mark ? styles.mark : undefined}>{d.tekst}</Text>
      ))}
    </>
  );
}

function Afgraens({ f, res, linjer, onType, onLinje, onFra, onTil, onNulstil }: {
  f: SoegFiltre;
  res: ReturnType<typeof soeg> | null;
  linjer: { linje: string; navn?: string | null }[];
  onType: (t: SoegType) => void;
  onLinje: (l: string | null) => void;
  onFra: (n: number | null) => void;
  onTil: (n: number | null) => void;
  onNulstil: (() => void) | null;
}) {
  const p = res?.personer.length ?? 0;
  const g = res?.godser.length ?? 0;
  const typer: [SoegType, string, number | null][] = [['alt', 'Alt', res ? p + g : null], ['personer', 'Personer', res ? p : null], ['besiddelser', 'Besiddelser', res ? g : null]];
  return (
    <View style={styles.afgraens}>
      <Mono size={9.5} color={Colors.inkMuted} style={styles.afgraensEtiket}>Type</Mono>
      <View style={styles.chipRow}>
        {typer.map(([v, navn, n]) => (
          <Chip key={v} label={n == null ? navn : `${navn} (${n})`} active={f.type === v} onPress={() => onType(v)} />
        ))}
      </View>
      {linjer.length > 0 ? (
        <>
          <Mono size={9.5} color={Colors.inkMuted} style={styles.afgraensEtiket}>Slægt og linje</Mono>
          <View style={styles.chipRow}>
            <Chip label="Hele slægten" active={f.linje == null} onPress={() => onLinje(null)} />
            {linjer.map((l) => (
              <Chip key={l.linje} label={l.navn ?? 'Linje uden navn'} active={f.linje === l.linje} onPress={() => onLinje(l.linje)} />
            ))}
          </View>
        </>
      ) : null}
      <Mono size={9.5} color={Colors.inkMuted} style={styles.afgraensEtiket}>Levetid</Mono>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <AarFelt vaerdi={f.fra} onAar={onFra} pladsholder="fra" label="Fra år" />
        <Body size={13} color={Colors.inkMuted}>–</Body>
        <AarFelt vaerdi={f.til} onAar={onTil} pladsholder="til" label="Til år" />
      </View>
      <Body size={11.5} color={Colors.inkMuted} style={{ marginTop: 5, lineHeight: 11.5 * 1.45 }}>
        En person tæller med, hvis levetiden rører perioden. Mangler fødsels- eller dødsår, regnes 100 år fra det kendte.
      </Body>
      {onNulstil ? (
        <Pressable onPress={onNulstil} accessibilityRole="button" style={{ marginTop: 8 }} hitSlop={6}>
          <BtnLabel size={12} color={Colors.bordeaux}>Nulstil afgrænsning</BtnLabel>
        </Pressable>
      ) : null}
    </View>
  );
}

// Årstal: skrives frit og sendes først videre, når feltet er tomt eller rummer et helt år (som web's AarFelt).
function AarFelt({ vaerdi, onAar, pladsholder, label }: { vaerdi: number | null; onAar: (n: number | null) => void; pladsholder: string; label: string }) {
  const [tekst, setTekst] = useState<string | null>(null);
  return (
    <TextInput
      style={styles.aarFelt}
      value={tekst ?? (vaerdi == null ? '' : String(vaerdi))}
      placeholder={pladsholder}
      placeholderTextColor={Colors.inkMuted}
      keyboardType="number-pad"
      accessibilityLabel={label}
      onChangeText={(v) => {
        const { tekst: t, aar } = aarFraTekst(v);
        setTekst(t);
        if (aar !== undefined) onAar(aar);
      }}
      onBlur={() => setTekst(null)}
    />
  );
}

function Chip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[styles.chip, active ? styles.chipActive : styles.chipIdle]} accessibilityRole="button" accessibilityState={{ selected: active }}>
      <BtnLabel size={11.5} color={active ? Colors.inkOnInverse : Colors.inkMuted}>{label}</BtnLabel>
    </Pressable>
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
      <BtnLabel size={11} color={active ? Colors.inkOnInverse : Colors.inkMuted}>{label}</BtnLabel>
    </Pressable>
  );
}

function PersonRow({ item, onPress }: { item: SearchItem; onPress: () => void }) {
  return (
    <Pressable style={styles.row} onPress={onPress}>
      <InitialBadge name={item.name} size={40} bg={Colors.surfaceSunken} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <Serif size={18} style={{ lineHeight: 19 }}>{item.name}</Serif>
        {item.years ? <Mono size={10} color={Colors.inkMuted}>{item.years}</Mono> : null}
      </View>
      <Serif size={18} color="#bcae93">›</Serif>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 18, paddingTop: 14, paddingBottom: 8 },
  input: {
    backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingHorizontal: 15,
    paddingVertical: 13,
    fontFamily: Fonts.sans,
    fontSize: 15,
    color: Colors.ink,
  },
  sortRow: { flexDirection: 'row', gap: 8, marginTop: 10, alignItems: 'center' },
  afgraens: {
    marginTop: 10, padding: 12, borderRadius: Radius.field, backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.medium,
  },
  afgraensEtiket: { letterSpacing: 9.5 * 0.16, textTransform: 'uppercase', marginBottom: 6, marginTop: 4 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginBottom: 6 },
  chip: { paddingHorizontal: 11, paddingVertical: 5, borderRadius: Radius.chip, borderWidth: StyleSheet.hairlineWidth },
  chipActive: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  chipIdle: { backgroundColor: Colors.surfaceRaised, borderColor: Border.medium },
  aarFelt: {
    width: 76, fontFamily: Fonts.mono, fontSize: 14, color: Colors.ink, paddingHorizontal: 8, paddingVertical: 6,
    borderRadius: 9, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.medium, backgroundColor: Colors.surfaceGround,
  },
  mark: { backgroundColor: Colors.bordeauxTint },
  stavLink: { color: Colors.bordeaux, fontFamily: Fonts.sansSemi },
  crest: {
    width: 40, height: 40, borderRadius: 8, backgroundColor: Colors.surfaceSunken,
    borderWidth: StyleSheet.hairlineWidth, borderColor: Border.faint, alignItems: 'center', justifyContent: 'center',
  },
  sortPill: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: Radius.chip,
    backgroundColor: Colors.surfaceSunken,
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
    backgroundColor: Colors.surfaceGround,
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

// Persondetalje (README §5.3). Header, barn-af, biografi (klamp 7 linjer/320 tegn + toggle),
// ægtefæller, børn pr. ægteskab, embeder, godser, materiale-tomtilstand, kilder, handlinger.
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { InitialBadge } from '../../components/InitialBadge';
import { TopBar } from '../../components/TopBar';
import { Body, Kicker, Mono, Serif } from '../../components/Typography';
import { childrenByMarriage, parentsOf, spousesOf } from '../../data/selectors';
import { useStore } from '../../store/useStore';
import { Border, Colors, Radius } from '../../theme/tokens';

const BIO_CLAMP = 320;

export default function PersonScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const meId = useStore((s) => s.meId);
  const setMe = useStore((s) => s.setMe);
  const setFocus = useStore((s) => s.setFocus);
  const [bioExpanded, setBioExpanded] = useState(false);

  const person = id && model ? model.byId[id] : null;

  if (!person || !model) {
    return (
      <View style={{ flex: 1 }}>
        <TopBar title="Person" />
        <View style={{ padding: 24 }}>
          <Body color={Colors.textMuted}>Personen blev ikke fundet.</Body>
        </View>
      </View>
    );
  }

  const isMe = meId === person.id;
  const parents = parentsOf(model, person.id);
  const spouses = spousesOf(model, person.id);
  const marriages = childrenByMarriage(model, person.id);
  const linje = aux?.linjeByPerson[person.id];
  const offices = aux?.officesBy[person.id] ?? [];
  const estates = aux?.estatesBy[person.id] ?? [];
  const sources = aux?.sourcesBy[person.id] ?? [];
  const media = aux?.mediaBy[person.id] ?? [];

  const bioLong = person.bio.length > BIO_CLAMP;
  const bioText = bioLong && !bioExpanded ? person.bio.slice(0, BIO_CLAMP).trimEnd() + '…' : person.bio;

  return (
    <View style={{ flex: 1 }}>
      <TopBar title={person.name} />
      <ScrollView contentContainerStyle={{ padding: 20, paddingBottom: 60 }}>
        {/* Header */}
        <View style={styles.headerRow}>
          <View style={styles.portrait} />
          <View style={{ flex: 1, gap: 4 }}>
            <Serif size={30}>{person.name}</Serif>
            {person.years ? <Mono size={11}>{person.years}</Mono> : null}
            <View style={styles.badgeRow}>
              {isMe ? <Badge text="★ Dig" /> : null}
              {linje ? <Badge text={`Linje ${linje}`} /> : null}
              {person.title ? <Badge text={person.title} tint={Colors.bordeauxFillLight2} /> : null}
            </View>
          </View>
        </View>

        {/* Barn af */}
        {parents.length ? (
          <Section title="Barn af">
            <Body size={14}>
              {parents.map((p, i) => (
                <Body key={p.id} size={14}>
                  <Body size={14} color={Colors.bordeaux} onPress={() => router.push(`/person/${p.id}`)}>
                    {p.name}
                  </Body>
                  {i < parents.length - 1 ? <Body size={14} color={Colors.textMuted}>{'  &  '}</Body> : null}
                </Body>
              ))}
            </Body>
          </Section>
        ) : null}

        {/* Biografi */}
        {person.bio ? (
          <Section title="Biografi">
            <Body size={14}>{bioText}</Body>
            {bioLong ? (
              <Pressable onPress={() => setBioExpanded((v) => !v)}>
                <Mono size={11} color={Colors.bordeaux} style={{ marginTop: 6 }}>
                  {bioExpanded ? 'Vis mindre' : 'Læs hele biografien'}
                </Mono>
              </Pressable>
            ) : null}
          </Section>
        ) : null}

        {/* Ægtefæller */}
        {spouses.length ? (
          <Section title="⚭ Gift med">
            {spouses.map((sp, i) => (
              <Body key={i} size={14} color={sp.id ? Colors.bordeaux : Colors.textSecondary}
                onPress={sp.id ? () => router.push(`/person/${sp.id}`) : undefined}>
                {sp.name}
              </Body>
            ))}
          </Section>
        ) : null}

        {/* Børn grupperet pr. ægteskab */}
        {marriages.some((m) => m.children.length) ? (
          <Section title="Børn">
            {marriages
              .filter((m) => m.children.length)
              .map((m) => (
                <View key={m.unionId} style={{ marginBottom: 12 }}>
                  {m.spouseName ? (
                    <Mono size={10} style={{ marginBottom: 6 }}>Børn med {m.spouseName}</Mono>
                  ) : null}
                  <View style={styles.childWrap}>
                    {m.children.map((c) => (
                      <Pressable key={c.id} style={styles.childItem} onPress={() => router.push(`/person/${c.id}`)}>
                        <InitialBadge name={c.name} size={40} />
                        <Body size={11} style={{ textAlign: 'center', maxWidth: 64 }} numberOfLines={1}>
                          {c.name.split(' ')[0]}
                        </Body>
                      </Pressable>
                    ))}
                  </View>
                </View>
              ))}
          </Section>
        ) : null}

        {/* Embeder */}
        {offices.length ? (
          <Section title="Embeder, rang & hverv">
            {offices.slice(0, 10).map((o, i) => (
              <View key={i} style={styles.lineItem}>
                <Body size={13} style={{ flex: 1 }}>{o.label}</Body>
                {o.period ? <Mono size={10}>{o.period}</Mono> : null}
              </View>
            ))}
            {offices.length > 10 ? <Mono size={10} color={Colors.textMuted}>+ {offices.length - 10} flere hverv</Mono> : null}
          </Section>
        ) : null}

        {/* Godser */}
        {estates.length ? (
          <Section title="Godser & besiddelser">
            <View style={styles.tagWrap}>
              {estates.map((e, i) => (
                <View key={i} style={styles.tag}>
                  <Body size={12} color={Colors.textSecondary}>
                    {e.navn}{e.period ? ` · ${e.period}` : ''}
                  </Body>
                </View>
              ))}
            </View>
          </Section>
        ) : null}

        {/* Materiale — tom-tilstand */}
        <Section title="Materiale">
          {media.length ? (
            <Body size={13} color={Colors.textMuted}>{media.length} medie-objekt(er) knyttet.</Body>
          ) : (
            <View style={styles.mediaEmpty}>
              {['Portræt', 'Våben', 'Dokument'].map((t) => (
                <View key={t} style={styles.mediaPlaceholder}>
                  <Mono size={9} color={Colors.textMuted}>{t}</Mono>
                </View>
              ))}
            </View>
          )}
        </Section>

        {/* Kilder */}
        {sources.length ? (
          <Section title="Kilder i Aarbogen">
            {sources.map((s, i) => (
              <View key={i} style={styles.lineItem}>
                <Body size={13} style={{ flex: 1 }}>{s.work}</Body>
                <Mono size={10}>{s.ref || 'trykt værk'}</Mono>
              </View>
            ))}
          </Section>
        ) : null}

        {/* Handlinger */}
        <View style={{ marginTop: 24, gap: 10 }}>
          <View style={{ flexDirection: 'row', gap: 10 }}>
            <ActionButton
              label="Vis i stamtræ"
              onPress={() => {
                setFocus(person.id);
                router.push('/tree');
              }}
            />
            <ActionButton
              label="Slægtskab"
              onPress={() => {
                useStore.setState({ relA: person.id });
                router.push('/relate');
              }}
            />
          </View>
          <Pressable
            style={[styles.meToggle, isMe && styles.meToggleActive]}
            onPress={() => setMe(isMe ? null : person.id)}>
            <Mono size={11} color={isMe ? Colors.bordeaux : Colors.textSecondary}>
              {isMe ? '★ Dette er dig — fjern markering' : 'Det er mig i slægten'}
            </Mono>
          </Pressable>
        </View>
      </ScrollView>
    </View>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={{ marginTop: 22 }}>
      <Kicker style={{ marginBottom: 8 }}>{title}</Kicker>
      {children}
    </View>
  );
}

function Badge({ text, tint = Colors.beige }: { text: string; tint?: string }) {
  return (
    <View style={[styles.badge, { backgroundColor: tint }]}>
      <Mono size={9} color={Colors.bordeaux} style={{ letterSpacing: 0 }}>{text}</Mono>
    </View>
  );
}

function ActionButton({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable style={styles.action} onPress={onPress}>
      <Mono size={11} color={Colors.paperBg}>{label}</Mono>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  headerRow: { flexDirection: 'row', gap: 16 },
  portrait: {
    width: 96,
    height: 120,
    borderRadius: Radius.card,
    backgroundColor: Colors.beige2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
  },
  badgeRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 6 },
  badge: { borderRadius: Radius.badge, paddingHorizontal: 8, paddingVertical: 3 },
  lineItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 5,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.faint,
  },
  childWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 14 },
  childItem: { alignItems: 'center', gap: 4, width: 64 },
  tagWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  tag: {
    backgroundColor: Colors.beige,
    borderRadius: Radius.chip,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  mediaEmpty: { flexDirection: 'row', gap: 10 },
  mediaPlaceholder: {
    width: 96,
    height: 120,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: Border.medium,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: Colors.paperCard,
  },
  action: {
    flex: 1,
    backgroundColor: Colors.bordeaux,
    borderRadius: Radius.field,
    paddingVertical: 12,
    alignItems: 'center',
  },
  meToggle: {
    borderWidth: 1,
    borderColor: Border.medium,
    borderRadius: Radius.field,
    paddingVertical: 12,
    alignItems: 'center',
  },
  meToggleActive: { borderColor: Colors.bordeaux, backgroundColor: Colors.bordeauxFillLight },
});

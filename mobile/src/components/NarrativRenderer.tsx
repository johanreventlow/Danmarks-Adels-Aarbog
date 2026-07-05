// Blok-niveau visning af fri-tekst med hyperlink-tokens + indlejrede billeder (billedstørrelser
// 2026-07-05, Slice C — udvider spec §5.2's inline-only renderer). RN tillader ikke et
// <Image>/<View> som barn af en <Text numberOfLines>-klamp-kæde, så bio-klampen (app/person/
// [id].tsx) bevares KUN for den simple, hyppige sag (ét afsnit, ingen billeder/overskrifter) —
// enhver narrativ med reel blok-struktur (billede eller overskrift, eller flere afsnit) renderes
// uklampet i stedet. Media-opløsning bruger IKKE et nyt netværkskald: hele media-tabellen er
// allerede bulk-loadet i modellen (aux.mediaById), så opslaget er synkront; kun signering af
// medium/large-URL'erne går gennem lib/media.ts's eksisterende useMediaAndThumbUris.
import React, { useMemo, useState } from 'react';
import { Image } from 'expo-image';
import { Pressable, Text, View, StyleSheet, type TextStyle } from 'react-native';
import { useRouter } from 'expo-router';
import { parseNarrativ, groupBlocks, type Block, type Segment } from '../lib/mentions';
import { useMediaAndThumbUris } from '../lib/media';
import { useStore } from '../store/useStore';
import { Colors } from '../theme/tokens';
import { Body, Serif } from './Typography';
import { Lightbox, type LightboxItem } from './Lightbox';

function renderInline(segs: Segment[], onPickPerson: (id: string) => void) {
  return segs.map((s, i) => {
    if (s.kind === 'text') return <Text key={i}>{s.text}</Text>;
    if (s.maalType === 'person') {
      return (
        <Text key={i} style={styles.link} onPress={() => onPickPerson(String(s.maalId))} accessibilityRole="link">
          {s.label}
        </Text>
      );
    }
    return <Text key={i} style={styles.linkInaktiv}>{s.label}</Text>;
  });
}

export function NarrativRenderer(props: {
  tekst: string;
  size?: number;
  color?: string;
  style?: TextStyle;
  numberOfLines?: number;
}) {
  const { tekst, size, color, style, numberOfLines } = props;
  const router = useRouter();
  const aux = useStore((s) => s.aux);
  const blocks = useMemo(() => groupBlocks(parseNarrativ(tekst)), [tekst]);

  const mediaRows = useMemo(() => {
    const seen = new Set<string>();
    const rows: NonNullable<typeof aux>['mediaById'][string][] = [];
    for (const b of blocks) {
      if (b.kind !== 'media') continue;
      const id = String(b.maalId);
      if (seen.has(id)) continue;
      const m = aux?.mediaById?.[id];
      if (m) { seen.add(id); rows.push(m); }
    }
    return rows;
  }, [blocks, aux]);
  const { uris: largeUris, thumbUris: mediumUris } = useMediaAndThumbUris(mediaRows, (m) => m.medium_storage_path);

  const [lightbox, setLightbox] = useState<number | null>(null);
  const lightboxItems: LightboxItem[] = [];
  const lightboxIndexByBlock: (number | null)[] = blocks.map((b) => {
    if (b.kind !== 'media') return null;
    const uri = largeUris[String(b.maalId)];
    if (!uri) return null;
    const row = mediaRows.find((r) => String(r.id) === String(b.maalId));
    lightboxItems.push({ id: String(lightboxItems.length), uri, titel: b.label || ((row?.titel as string | undefined) ?? null) });
    return lightboxItems.length - 1;
  });

  const onPickPerson = (id: string) => router.push(`/person/${id}`);

  // Bio-klamp (numberOfLines) bevares for enhver rent tekstlig narrativ (kun afsnit, uanset antal) —
  // RN klamper fint på tværs af indlejrede '\n' i ÉT <Text>-træ. Kun billeder/overskrifter kræver
  // den uklampede multi-blok-visning nedenfor, da RN ikke kan klampe på tværs af flere <Text>-træer.
  if (blocks.every((b) => b.kind === 'paragraph')) {
    const segs: Segment[] = [];
    blocks.forEach((b, i) => {
      if (b.kind !== 'paragraph') return;
      if (i > 0) segs.push({ kind: 'text', text: '\n\n' });
      segs.push(...b.segs);
    });
    return (
      <Body size={size} color={color} style={style} numberOfLines={numberOfLines}>
        {renderInline(segs, onPickPerson)}
      </Body>
    );
  }

  return (
    <View style={style}>
      {blocks.map((b, i) => {
        if (b.kind === 'heading') {
          return <Serif key={i} size={(size ?? 14) + 4} style={styles.heading}>{b.text}</Serif>;
        }
        if (b.kind === 'media') {
          const lightboxIndex = lightboxIndexByBlock[i];
          const mediumUri = mediumUris[String(b.maalId)] ?? largeUris[String(b.maalId)];
          if (lightboxIndex == null || !mediumUri) {
            return <Body key={i} size={size} color={Colors.textMuted} style={styles.mediaFallback}>{b.label || '[billede]'}</Body>;
          }
          const row = mediaRows.find((r) => String(r.id) === String(b.maalId));
          const cap = b.label || (row?.titel as string | undefined) || '';
          return (
            <View key={i} style={styles.mediaBlock}>
              <Pressable onPress={() => setLightbox(lightboxIndex)}>
                <Image source={{ uri: mediumUri }} style={styles.mediaImage} contentFit="cover" />
              </Pressable>
              {cap ? <Body size={(size ?? 14) - 2} color={Colors.textMuted} style={styles.mediaCaption}>{cap}</Body> : null}
            </View>
          );
        }
        return (
          <Body key={i} size={size} color={color} style={styles.paragraph}>
            {renderInline(b.segs, onPickPerson)}
          </Body>
        );
      })}
      {lightbox != null ? (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  link: { color: Colors.bordeaux, textDecorationLine: 'underline' },
  linkInaktiv: { color: Colors.textMuted },
  heading: { marginTop: 10, marginBottom: 4 },
  paragraph: { marginBottom: 8 },
  mediaBlock: { marginVertical: 10 },
  mediaImage: { width: '100%', aspectRatio: 4 / 3, borderRadius: 10, backgroundColor: Colors.beige2 },
  mediaCaption: { marginTop: 4 },
  mediaFallback: { marginVertical: 6, fontStyle: 'italic' },
});

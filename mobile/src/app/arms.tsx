// Slægtens våben (README §5.9) — mobilens pendant til web's ArmsView: hovedvåbnet (første coat_of_arms i id-orden)
// med billede og blasonering, varianterne med hver sit billede, og bogens våbengalleri (medier af slags 'våben', uden
// dem der allerede står ovenfor). Alt er hentet ved opstart (aux: coat_of_arms, media→coat_of_arms, media), så skærmen
// laver ingen nye kald; kun signeringen af billed-URL'erne. Mangler et billede, står den stribede pladsholder.
import { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Lightbox } from '../components/Lightbox';
import { LoadGate } from '../components/LoadGate';
import { SignedImage } from '../components/SignedImage';
import { StripedPlaceholder } from '../components/StripedPlaceholder';
import { TopBar } from '../components/TopBar';
import { Body, Mono, Serif } from '../components/Typography';
import type { RawMedia } from '../data/types';
import { vaabenSide, variantTitel } from '../data/vaaben';
import { useObjektMedia } from '../lib/media';
import { useStore } from '../store/useStore';
import { Border, Colors, Fonts, Radius, Shadow } from '../theme/tokens';

export default function ArmsScreen() {
  const aux = useStore((s) => s.aux);
  const [lightbox, setLightbox] = useState<number | null>(null);
  const side = useMemo(() => (aux ? vaabenSide(aux) : { hoved: null, varianter: [], galleri: [] }), [aux]);

  // Én signering for alle billeder på siden; derefter vælges det første signerbare billede pr. våben (som web's
  // firstSignable — ikke blindt media[0]).
  const alleMedier = useMemo(() => {
    const set = new Map<string, RawMedia>();
    for (const m of [...(side.hoved?.media ?? []), ...side.varianter.flatMap((v) => v.media), ...side.galleri]) set.set(String(m.id), m);
    return [...set.values()];
  }, [side]);
  const { items } = useObjektMedia(alleMedier);
  const signeret = useMemo(() => new Map(items.map((it) => [String(it.media.id), it])), [items]);
  const foersteSignerbare = (media: RawMedia[]) => media.map((m) => signeret.get(String(m.id))).find(Boolean) ?? null;

  const hovedBillede = side.hoved ? foersteSignerbare(side.hoved.media) : null;
  const variantBilleder = side.varianter.map((v) => foersteSignerbare(v.media));
  const galleri = side.galleri.map((m) => signeret.get(String(m.id))).filter((x): x is NonNullable<typeof x> => !!x);
  // Hovedvåben, varianter og galleri er ÉT navigerbart sæt i Lightbox (som web).
  const lightboxItems = [hovedBillede, ...variantBilleder, ...galleri]
    .filter((x): x is NonNullable<typeof x> => !!x)
    .map((x) => ({ id: String(x.media.id), uri: x.uri, titel: x.media.titel, kunstner: x.media.kunstner, datering: x.media.datering }));
  const aabn = (mediaId: string | number) => setLightbox(lightboxItems.findIndex((x) => x.id === String(mediaId)));

  return (
    <View style={{ flex: 1 }}>
      <TopBar title="Slægtens våben" />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          <Mono size={10} color={Colors.inkMuted} style={{ letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
            Autoriseret våben
          </Mono>
          <Body size={12} color={Colors.inkMuted} style={{ marginBottom: 14 }}>
            Dansk Adelsforenings gældende gengivelse
          </Body>

          <View style={styles.armCard}>
            {hovedBillede ? (
              <Pressable onPress={() => aabn(hovedBillede.media.id)} accessibilityRole="imagebutton"
                accessibilityLabel={hovedBillede.media.titel ? String(hovedBillede.media.titel) : 'Slægtens våben'}>
                <SignedImage uri={hovedBillede.uri} style={{ width: 150, height: 185, borderRadius: 10 }} contentFit="contain" />
              </Pressable>
            ) : (
              <StripedPlaceholder width={150} height={185} radius={10} label="våbenskjold" />
            )}
            <Mono size={8.5} color={Colors.goldInk} style={{ marginTop: 14, letterSpacing: 8.5 * 0.1, textTransform: 'uppercase' }}>
              Blasonering
            </Mono>
            <Serif size={16} italic color={Colors.inkSecondary} style={{ textAlign: 'center', marginTop: 5, lineHeight: 16 * 1.45, fontFamily: Fonts.serifItalic }}>
              {side.hoved?.blasonering || 'Blasonering ikke registreret.'}
            </Serif>
            {side.hoved?.note ? (
              <Body size={12} color={Colors.inkMuted} style={{ textAlign: 'center', marginTop: 8, lineHeight: 12 * 1.45 }}>
                {side.hoved.note}
              </Body>
            ) : null}
          </View>

          {side.varianter.length > 0 && (
            <>
              <Mono size={10} color={Colors.inkMuted} style={{ marginTop: 26, marginBottom: 14, letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
                Øvrige gengivelser & varianter
              </Mono>
              <View style={styles.grid}>
                {side.varianter.map((v, i) => {
                  const b = variantBilleder[i];
                  return (
                    <View key={v.id} style={styles.variant}>
                      {b ? (
                        <Pressable onPress={() => aabn(b.media.id)} accessibilityRole="imagebutton" accessibilityLabel={variantTitel(v)}>
                          <SignedImage uri={b.thumbUri} style={{ width: '100%', aspectRatio: 0.82, borderRadius: 8 }} contentFit="contain" />
                        </Pressable>
                      ) : (
                        <StripedPlaceholder radius={8} style={{ width: '100%', aspectRatio: 0.82 }} />
                      )}
                      <Serif size={15} style={{ marginTop: 7, lineHeight: 16 }}>{variantTitel(v)}</Serif>
                    </View>
                  );
                })}
              </View>
            </>
          )}

          {galleri.length > 0 && (
            <>
              <Mono size={10} color={Colors.inkMuted} style={{ marginTop: 26, marginBottom: 14, letterSpacing: 10 * 0.1, textTransform: 'uppercase' }}>
                Våben i Danmarks Adels Aarbog 2018-20
              </Mono>
              <View style={styles.grid}>
                {galleri.map((g) => (
                  <View key={String(g.media.id)} style={styles.variant}>
                    <Pressable onPress={() => aabn(g.media.id)} accessibilityRole="imagebutton"
                      accessibilityLabel={g.media.titel ? String(g.media.titel) : 'Våben'}>
                      <SignedImage uri={g.thumbUri} style={{ width: '100%', aspectRatio: 0.82, borderRadius: 8 }} contentFit="contain" />
                    </Pressable>
                    {g.media.titel ? (
                      <Body size={12} color={Colors.inkSecondary} style={{ marginTop: 7, lineHeight: 12 * 1.3 }}>{g.media.titel}</Body>
                    ) : null}
                  </View>
                ))}
              </View>
            </>
          )}

          <View style={styles.note}>
            <Body size={12} color={Colors.inkMuted} style={{ lineHeight: 12 * 1.5 }}>
              Varianter, briseringer og daterede segl tilføjes efterhånden som de digitaliseres.
            </Body>
          </View>
        </ScrollView>
      </LoadGate>
      {lightbox != null && lightbox >= 0 && (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  armCard: {
    backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.medium,
    borderRadius: 16,
    padding: 22,
    alignItems: 'center',
    ...Shadow.card,
  },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 11 },
  variant: {
    width: '47%',
    flexGrow: 1,
    backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 12,
    padding: 11,
  },
  note: {
    marginTop: 14,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: 'rgba(34,31,26,0.2)',
    borderRadius: Radius.field,
    padding: 13,
    backgroundColor: Colors.surfaceRaised,
  },
});

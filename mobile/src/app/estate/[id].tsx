// Gods-detalje (README §5.8) — mobilens pendant til web's BesiddelseSide (EstatesView.tsx, fase 7b): »Besiddelse ·
// sted« over navnet, godsets historie fra Aarbogen, billeder, minikort og ejerrækken (byggEjerraekke i @daa/core:
// kronologisk efter periodens første årstal, ejere læseren ikke kan se udelades, rækker uden årstal for sig).
// Historie og sted hentes pr. skærm (hentBesiddelseInfo) med en synlig fejl; billederne og ejerne er hentet ved opstart.
import { byggEjerraekke, type EjerRaekke } from '@daa/core';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { GeoMap } from '../../components/GeoMap';
import { Lightbox } from '../../components/Lightbox';
import { LoadGate } from '../../components/LoadGate';
import { NarrativRenderer } from '../../components/NarrativRenderer';
import { SignedImage } from '../../components/SignedImage';
import { TopBar } from '../../components/TopBar';
import { Body, BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { ejerRelationer, hentBesiddelseInfo } from '../../data/besiddelser';
import type { RawMedia } from '../../data/types';
import { useGeoOnMount } from '../../hooks/useGeoOnMount';
import { useHentning } from '../../hooks/useHentning';
import { useObjektMedia } from '../../lib/media';
import { supabase } from '../../lib/supabase';
import { useStore } from '../../store/useStore';
import { Colors, Fonts, Radius } from '../../theme/tokens';

const INGEN_MEDIER: RawMedia[] = [];

export default function EstateScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const geo = useStore((s) => s.geo);
  const geoLoading = useStore((s) => s.geoLoading);
  const [lightbox, setLightbox] = useState<number | null>(null);

  const estate = id && aux ? aux.estateById[id] ?? null : null;
  const point = id ? geo.byEstate[id] : null;
  const stedId = estate?.stedId ?? null;
  const owners = id && aux ? aux.ownersByEstate[id] : undefined;
  const raekke = useMemo(() => (model ? byggEjerraekke(ejerRelationer(owners ?? []), model) : null), [owners, model]);
  const { items: billeder, lightboxItems } = useObjektMedia((id && aux?.mediaByObjekt[`estate:${id}`]) || INGEN_MEDIER);

  const hent = useCallback(() => hentBesiddelseInfo(supabase, id ?? '', stedId), [id, stedId]);
  const info = useHentning(estate ? `${estate.id}|${stedId ?? ''}` : null, hent);

  // Lazy geo-kæde (review 27 P3): gods-detaljen viser et minikort for godsets sted — udløs
  // hentningen ved mount.
  useGeoOnMount();

  const visPerson = (pid: string) => router.push(`/person/${pid}`);

  return (
    <View style={{ flex: 1 }}>
      <TopBar title={estate?.navn ?? 'Besiddelse'} />
      <LoadGate>
        <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingBottom: 40 }}>
          {!estate ? (
            <View>
              <Serif size={20}>Besiddelsen findes ikke i Aarbogen</Serif>
              <Body size={13} color={Colors.inkMuted} style={{ marginTop: 6 }}>
                Linket peger på en besiddelse, Aarbogen ikke har, eller som er fjernet.
              </Body>
              <Pressable onPress={() => router.push('/estates')} style={{ marginTop: 12 }} accessibilityRole="link">
                <BtnLabel size={13} color={Colors.bordeaux}>Alle slægtens besiddelser ›</BtnLabel>
              </Pressable>
            </View>
          ) : (
            <>
              <Mono size={10} color={Colors.goldInk} style={{ letterSpacing: 10 * 0.16, textTransform: 'uppercase', marginBottom: 6 }}>
                {['Besiddelse', info.data?.sted].filter(Boolean).join(' · ')}
              </Mono>
              <Serif size={32} style={{ lineHeight: 33 }}>{estate.navn}</Serif>
              {estate.slags ? (
                <View style={styles.slagsBadge}>
                  <BtnLabel size={11.5} color={Colors.bordeaux}>{estate.slags}</BtnLabel>
                </View>
              ) : null}

              {info.status === 'fejl' ? (
                <View style={styles.fejlBoks} accessibilityRole="alert">
                  <Body size={13} color={Colors.danger}>Godsets historie kunne ikke hentes.</Body>
                  <Body size={12.5} color={Colors.inkMuted} style={{ marginTop: 4 }}>Forbindelsen til arkivet svigtede et øjeblik.</Body>
                  <Pressable onPress={() => void info.genhent()} accessibilityRole="button" hitSlop={8} style={{ marginTop: 8 }}>
                    <BtnLabel size={12} color={Colors.bordeaux}>Prøv igen</BtnLabel>
                  </Pressable>
                </View>
              ) : info.status === 'henter' ? (
                <Body size={12.5} color={Colors.inkMuted} style={{ marginTop: 14 }}>Henter godsets historie …</Body>
              ) : info.data?.narrativ ? (
                <View style={{ marginTop: 14 }}>
                  <NarrativRenderer tekst={info.data.narrativ} size={15.5} color={Colors.inkSecondary} />
                </View>
              ) : null}

              {billeder.length > 0 && (
                <View style={styles.billeder}>
                  {billeder.map((b, i) => (
                    <Pressable key={String(b.media.id)} onPress={() => setLightbox(i)} accessibilityRole="imagebutton"
                      accessibilityLabel={b.media.titel ? String(b.media.titel) : 'Billede af besiddelsen'}
                      style={i === 0 ? styles.hovedBillede : styles.lilleBillede}>
                      <SignedImage uri={i === 0 ? b.uri : b.thumbUri} style={{ width: '100%', height: '100%' }} contentFit="cover" />
                    </Pressable>
                  ))}
                </View>
              )}

              {geoLoading ? (
                <View style={{ marginTop: 14 }}>
                  <Body size={12.5} color={Colors.inkMuted}>Indlæser kort…</Body>
                </View>
              ) : point && (
                <View style={{ marginTop: 14 }}>
                  <GeoMap points={[point]} mode="mini" />
                </View>
              )}

              <Kicker size={9.5} style={{ marginTop: 24, marginBottom: 12, letterSpacing: 9.5 * 0.14 }}>
                Ejerrækken
              </Kicker>
              {!raekke || raekke.raekker.length + raekke.udenAar.length === 0 ? (
                <Body size={13.5} color={Colors.inkSecondary}>Aarbogen nævner ingen ejere af {estate.navn}.</Body>
              ) : (
                <>
                  <EjerListe raekker={raekke.raekker} onPick={visPerson} />
                  {raekke.udenAar.length > 0 && (
                    <>
                      <Mono size={9.5} color={Colors.inkMuted} style={{ marginTop: 8, marginBottom: 10, letterSpacing: 9.5 * 0.14, textTransform: 'uppercase' }}>
                        Uden årstal i bogen
                      </Mono>
                      <EjerListe raekker={raekke.udenAar} onPick={visPerson} />
                    </>
                  )}
                  <Body size={12} color={Colors.inkMuted} style={{ lineHeight: 12 * 1.5 }}>
                    Ejerne er slægtens medlemmer, som Aarbogen nævner som ejere, i rækkefølge efter periodens første årstal.
                    Perioderne står, som bogen skriver dem.
                  </Body>
                </>
              )}

              <View style={styles.kilde}>
                <Serif size={16} color={Colors.bordeaux}>§</Serif>
                <View style={{ flex: 1 }}>
                  <BtnLabel size={12.5} color={Colors.ink}>Danmarks Adels Aarbog</BtnLabel>
                  <Mono size={10} color={Colors.inkMuted}>ejerperioder fra personernes stamtavleposter</Mono>
                </View>
              </View>
            </>
          )}
        </ScrollView>
      </LoadGate>
      {lightbox != null && (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      )}
    </View>
  );
}

function EjerListe({ raekker, onPick }: { raekker: EjerRaekke[]; onPick: (id: string) => void }) {
  return (
    <View>
      {raekker.map((r, i) => {
        const last = i === raekker.length - 1;
        const under = [r.years, r.linje].filter(Boolean).join(' · ');
        return (
          <View key={`${r.personId}|${r.periode}|${i}`} style={{ flexDirection: 'row', gap: 13, alignItems: 'flex-start' }}>
            <View style={styles.dotCol}>
              <View style={styles.dot} />
              {!last ? <View style={styles.line} /> : null}
            </View>
            <Pressable style={{ flex: 1, paddingBottom: 16 }} onPress={() => onPick(r.personId)} accessibilityRole="link">
              <Mono size={10.5} color={Colors.inkMuted}>{r.periode || 'ingen periode'}</Mono>
              <Serif size={19} color={Colors.ink} style={{ marginTop: 1, lineHeight: 20, fontFamily: Fonts.serifSemi }}>
                {r.navn} ›
              </Serif>
              {under ? <Body size={12} color={Colors.inkMuted} style={{ marginTop: 2 }}>{under}</Body> : null}
            </Pressable>
          </View>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  slagsBadge: {
    alignSelf: 'flex-start',
    marginTop: 9,
    backgroundColor: Colors.bordeauxFillLight2,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(136,26,51,0.16)',
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  fejlBoks: {
    marginTop: 14,
    borderWidth: 1,
    borderColor: Colors.bordeaux,
    borderRadius: Radius.field,
    padding: 14,
    backgroundColor: Colors.surfaceRaised,
  },
  billeder: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginTop: 16 },
  hovedBillede: { width: '100%', height: 220, borderRadius: 14, overflow: 'hidden', backgroundColor: Colors.surfaceSunken },
  lilleBillede: { width: 96, height: 72, borderRadius: 10, overflow: 'hidden', backgroundColor: Colors.surfaceSunken },
  kilde: { flexDirection: 'row', gap: 10, alignItems: 'flex-start', marginTop: 18 },
  dotCol: { width: 13, alignItems: 'center', paddingTop: 6 },
  dot: { width: 11, height: 11, borderRadius: Radius.round, backgroundColor: Colors.bordeaux },
  line: { width: 2, flex: 1, minHeight: 26, backgroundColor: 'rgba(136,26,51,0.22)', marginTop: 2 },
});

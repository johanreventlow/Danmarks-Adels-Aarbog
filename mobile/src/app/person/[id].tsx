// Persondetalje (README §5.3) — tro port af v2-designet (linje 395-543): stribet portræt-
// pladsholder, inline "barn af"/"gift med" i Cormorant, badges (Dig/Linje/titel), bio-klamp
// 7 linjer, børn pr. ægteskab (50px avatarer), embeder, godser-tags, materiale-tomtilstand,
// kilder m. §-tegn + "trykt værk", handlinger. 6e (paritetsplanens batch 5): udgavevælger, linjemærker for den
// valgte udgave og B6-noter (data/personUdgave.ts, som web's usePersonVisning).
import { SignedImage } from '../../components/SignedImage';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { GeoMap } from '../../components/GeoMap';
import { Lightbox } from '../../components/Lightbox';
import { NarrativRenderer } from '../../components/NarrativRenderer';
import { StripedPlaceholder } from '../../components/StripedPlaceholder';
import { TopBar } from '../../components/TopBar';
import { Body, BtnLabel, Kicker, Mono, Serif } from '../../components/Typography';
import { formelNavneform, lifeJourney, personensAdelsnavn } from '@daa/core';
import type { BioSourceVersion } from '@daa/core';
import { byggPersonUdgave } from '../../data/personUdgave';
import { fetchPublicBioVersionsForPerson } from '../../data/publicBioVersions';
import { childrenByMarriage, parentsOf, spousesOf } from '../../data/selectors';
import { erPortraetSlags, usePersonMedia } from '../../lib/media';
import { supabase } from '../../lib/supabase';
import { selectMeId, useStore } from '../../store/useStore';
import { Border, Colors, Fonts, Radius } from '../../theme/tokens';

const BIO_CLAMP_CHARS = 320;
const BIO_CLAMP_LINES = 7;

export default function PersonScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const aux = useStore((s) => s.aux);
  const geo = useStore((s) => s.geo);
  const meId = useStore(selectMeId);
  const setMe = useStore((s) => s.setMe);
  const setFocus = useStore((s) => s.setFocus);
  const canonicalId = useStore((s) => s.canonicalId);
  const status = useStore((s) => s.status);
  const [bioExpanded, setBioExpanded] = useState(false);
  const [lightbox, setLightbox] = useState<number | null>(null); // Slice A
  const [bioVersionResult, setBioVersionResult] = useState<{ personId: string; versions: BioSourceVersion[] | null } | null>(null);
  // Læserens udgavevalg, bundet til personen og chippens identitet (som web): en anden person giver standarden.
  const [valg, setValg] = useState<{ personId: string; sourceId: string } | null>(null);

  // Lazy geo-kæde (review 27 P3): persondetaljen viser et livsrejse-minikort hvis personen har
  // geo-punkter — udløs hentningen ved mount (mirror af web's Folgesvend.tsx detailOpen-trigger).
  // Gates + re-kører på status (ikke tomme deps): _layout.tsx monterer person/[id] uafhængigt
  // af load()-status (fx direkte deep-link), så et for-tidligt kald ellers aldrig ville
  // genforsøges når data ankommer (dual-review-fund, se kort.tsx). Ingen loading-placeholder
  // her (bevidst, spejler web): de FLESTE personer ender uden geo-punkter, så en midlertidig
  // boks ville flimre op og forsvinde for langt de fleste besøg.
  useEffect(() => {
    if (status === 'ready') useStore.getState().loadGeo();
  }, [status]);

  // Resolv rute-id til kanonisk: et link til enten et alias (fx III-58) eller den kanoniske (V-1)
  // lander på den samme, samlede person (samme_som-collapse).
  const personId = id ? canonicalId(String(id)) : null;
  const person = personId && model ? model.byId[personId] : null;

  useEffect(() => {
    let current = true;
    if (!personId || !supabase) return () => { current = false; };
    fetchPublicBioVersionsForPerson(supabase, personId, person?.mergedFrom).then((versions) => {
      if (current) setBioVersionResult({ personId, versions });
    }).catch(() => { if (current) setBioVersionResult({ personId, versions: null }); });
    return () => { current = false; };
  }, [personId, person?.mergedFrom]);

  // Medier (mediehåndtering Slice 0): model-hook FØR early-return så hook-kaldet er ubetinget.
  // lightboxItems (portræt+galleri, ÉT navigerbart sæt) bygges af hooken selv (Slice A).
  const media = personId ? aux?.mediaBy[personId] ?? [] : [];
  const { portraitItem, gallery, lightboxItems } = usePersonMedia(media);

  if (!person || !model) {
    return (
      <View style={{ flex: 1 }}>
        <TopBar title="Person" />
        <View style={{ padding: 24 }}>
          <Body color={Colors.inkMuted}>Personen blev ikke fundet.</Body>
        </View>
      </View>
    );
  }

  // meId er allerede kanoniseret ved læsning (selectMeId, review 27 M-K3) — robust uanset
  // hydrate/load-rækkefølge, så sammenligningen kan ske direkte.
  const isMe = meId != null && meId === person.id;
  const parents = parentsOf(model, person.id);
  const spouses = spousesOf(model, person.id);
  const marriages = childrenByMarriage(model, person.id).filter((m) => m.children.length);
  // Bogens formelle navneform (»Johan Martin greve af Reventlow«; plan 2026-11-26) — samme regel som web: linjens
  // adelsnavn via den kanoniske linjemodel, ingen for stifteren, kun med adelstitel.
  const formelNavn = model.lineage && model.adelsnavne
    ? formelNavneform({ fornavne: person.fornavne, titel: person.title, adelsnavn: personensAdelsnavn(person.id, model.lineage, model.adelsnavne), slaegtsnavn: model.slaegtsnavn })
    : null;
  const journey = lifeJourney(geo, person.id);
  const offices = aux?.officesBy[person.id] ?? [];
  const estates = aux?.estatesBy[person.id] ?? [];
  // Udgavevælger (én chip pr. udgave, standard = nyeste udgave med en post), linjerne i den valgte udgave, B6-noter
  // og »Kilde i Aarbogen« — samme regler som web. »Optræder i Aarbogen som« er fjernet som på web (e0618472):
  // kilderne står nederst på siden.
  const bioVersions = bioVersionResult?.personId === personId ? bioVersionResult.versions : null;
  const v = byggPersonUdgave(model, person.id, {
    bioVersions,
    valgtUdgaveId: valg?.personId === person.id ? valg.sourceId : null,
    fallbackBio: person.bio,
    fallbackKilder: aux?.sourcesBy[person.id] ?? [],
  });
  const vaelgChip = (idx: number) => {
    const c = v.vaelger.chips[idx];
    if (c) setValg({ personId: person.id, sourceId: c.sourceId });
  };
  const sources = v.sources;
  const activeBio = v.bioText;
  // Vis udfold-toggle hvis bio enten er lang (tegn) ELLER har mange linjeskift — ellers
  // ville en kort men afsnits-opdelt prosa blive klampet til 7 linjer uden mulighed for udfold.
  const bioNewlines = (activeBio.match(/\n/g)?.length ?? 0);
  const bioLong = activeBio.length > BIO_CLAMP_CHARS || bioNewlines >= BIO_CLAMP_LINES;

  return (
    <View style={{ flex: 1 }}>
      <TopBar title={person.name} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 28 }}>
        {/* Header: portræt + navn + badges */}
        <View style={styles.header}>
          {portraitItem ? (
            <Pressable onPress={() => setLightbox(0)}>
              <SignedImage uri={portraitItem.thumbUri} style={{ width: 96, height: 120, borderRadius: 12, backgroundColor: Colors.surfaceSunken }} contentFit={erPortraetSlags(portraitItem.media.slags) ? 'cover' : 'contain'} transition={150} />
            </Pressable>
          ) : (
            <StripedPlaceholder width={96} height={120} radius={12} label="portræt" />
          )}
          <View style={{ flex: 1, minWidth: 0, paddingTop: 4 }}>
            <Serif size={30} style={{ lineHeight: 30 }}>{person.name}</Serif>
            {person.years ? <Mono size={11} color={Colors.inkMuted} style={{ marginTop: 7 }}>{person.years}</Mono> : null}
            <View style={styles.badgeRow}>
              {isMe ? (
                <View style={[styles.badge, { backgroundColor: Colors.bordeaux }]}>
                  <BtnLabel size={11} color={Colors.inkOnInverse} style={{ fontFamily: Fonts.sansBold }}>★ Dig</BtnLabel>
                </View>
              ) : null}
              {v.hovedLinjer.map((navn) => (
                <View key={navn} style={[styles.badge, styles.badgeBordered, { backgroundColor: Colors.surfaceSunken }]}>
                  <Mono size={10} color={Colors.inkMuted} style={{ letterSpacing: 0 }}>{navn}</Mono>
                </View>
              ))}
              {person.title ? (
                <View style={[styles.badge, { backgroundColor: Colors.bordeauxFillLight2, borderWidth: StyleSheet.hairlineWidth, borderColor: 'rgba(136,26,51,0.16)' }]}>
                  <BtnLabel size={11.5} color={Colors.bordeaux}>{person.title}</BtnLabel>
                </View>
              ) : null}
            </View>
            {formelNavn ? (
              <View style={{ marginTop: 9 }}>
                <Kicker color={Colors.inkMuted}>I Aarbogen</Kicker>
                <Serif size={16} style={{ marginTop: 2, lineHeight: 16 * 1.3 }}>{formelNavn}</Serif>
              </View>
            ) : null}
            {v.vaelger.form !== 'ingen' ? (
              <View style={styles.udgaveRow} accessibilityRole="radiogroup" accessibilityLabel="Udgave">
                {v.vaelger.chips.map((c, i) => (
                  <Pressable key={c.sourceId} onPress={() => vaelgChip(i)} accessibilityRole="radio"
                    accessibilityState={{ selected: i === v.valgtIdx }}
                    style={[styles.udgaveChip, i === v.valgtIdx ? styles.udgaveChipActive : null]}>
                    <BtnLabel size={11.5} color={i === v.valgtIdx ? Colors.bordeaux : Colors.inkSecondary}>{c.label}</BtnLabel>
                  </Pressable>
                ))}
              </View>
            ) : null}
            {v.tidligereUdgave ? (
              <Body size={11} color={Colors.inkMuted} style={styles.udgaveNote}>Du ser en tidligere udgave.</Body>
            ) : null}
            {v.linjeNoter.map((n) => (
              <Body key={n} size={11} color={Colors.inkMuted} style={styles.udgaveNote}>{n}</Body>
            ))}
          </View>
        </View>

        {/* Barn af — inline Cormorant */}
        {parents.length ? (
          <View style={styles.barnAf}>
            <Kicker size={9} color={Colors.goldInk} style={{ letterSpacing: 9 * 0.1 }}>Barn af</Kicker>
            {parents.map((p, i) => (
              <View key={p.id} style={styles.inlineItem}>
                {i > 0 ? <Serif size={16} italic color={Colors.goldInk} style={{ fontFamily: Fonts.serifItalic }}>&</Serif> : null}
                <Serif size={17} color={Colors.bordeaux} onPress={() => router.push(`/person/${p.id}`)}>{p.name} ›</Serif>
              </View>
            ))}
          </View>
        ) : null}

        {/* Biografi — klamp 7 linjer */}
        {v.bioManglerIUdgave ? (
          <View style={styles.block}>
            <Body size={13} color={Colors.inkMuted}>Ingen biografi fra denne udgave.</Body>
          </View>
        ) : null}
        {activeBio ? (
          <View style={styles.block}>
            <NarrativRenderer tekst={activeBio} size={14} color={Colors.inkSecondary}
              style={{ lineHeight: 14 * 1.55 }}
              numberOfLines={bioExpanded ? undefined : BIO_CLAMP_LINES} />
            {bioLong ? (
              <Pressable onPress={() => setBioExpanded((v) => !v)}>
                <BtnLabel size={12.5} color={Colors.bordeaux} style={{ marginTop: 8 }}>
                  {bioExpanded ? 'Vis mindre' : 'Læs hele biografien'}
                </BtnLabel>
              </Pressable>
            ) : null}
          </View>
        ) : null}

        {/* Livsrejse: kun hvis personen har mindst ét geo-punkt (ingen tom-boks-støj). */}
        {journey.length > 0 ? (
          <View style={styles.block}>
            <Kicker size={9.5} style={{ marginBottom: 8, letterSpacing: 9.5 * 0.14 }}>Livsrejse</Kicker>
            <GeoMap
              points={journey}
              mode="mini"
              onPointPress={(p) => p.personId && p.personId !== person.id && router.push(`/person/${p.personId}`)}
            />
          </View>
        ) : null}

        {/* ⚭ gift med — inline Cormorant kursiv */}
        {spouses.length ? (
          <View style={styles.block}>
            <Serif size={16} italic color={Colors.inkMuted} style={{ lineHeight: 16 * 1.5, fontFamily: Fonts.serifItalic }}>
              {'⚭ gift med  '}
              {spouses.map((sp, i) => (
                <Serif key={i} size={16} italic={!sp.id}
                  color={sp.id ? Colors.bordeaux : Colors.inkMuted}
                  style={{ fontFamily: sp.id ? Fonts.serifSemi : Fonts.serifItalic }}
                  onPress={sp.id ? () => router.push(`/person/${sp.id}`) : undefined}>
                  {i > 0 ? '· ' : ''}{sp.name}{sp.id ? ' ›' : ''}
                </Serif>
              ))}
            </Serif>
          </View>
        ) : null}

        {/* Børn grupperet pr. ægteskab */}
        {marriages.length ? (
          <View style={{ marginTop: 20 }}>
            {marriages.map((m) => (
              <View key={m.unionId} style={{ marginBottom: 4 }}>
                <Kicker size={9.5} style={{ paddingHorizontal: 22, marginBottom: 10 }}>
                  {m.spouseName ? `Børn med ${m.spouseName}` : 'Børn'}
                </Kicker>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, paddingHorizontal: 22, paddingBottom: 14 }}>
                  {m.children.map((c) => (
                    <Pressable key={c.id} style={styles.childItem} onPress={() => router.push(`/person/${c.id}`)}>
                      <View style={styles.childAvatar}>
                        <Serif size={19} color={Colors.bordeaux}>{c.name[0]?.toUpperCase() ?? '?'}</Serif>
                      </View>
                      <Body size={11} color={Colors.ink} style={{ textAlign: 'center', marginTop: 6, lineHeight: 13, fontFamily: Fonts.sansSemi }} numberOfLines={2}>
                        {c.name.split(' ')[0]}
                      </Body>
                    </Pressable>
                  ))}
                </ScrollView>
              </View>
            ))}
          </View>
        ) : null}

        {/* Embeder */}
        {offices.length ? (
          <Section title="Embeder, rang & hverv">
            {offices.slice(0, 10).map((o, i) => (
              <View key={i} style={styles.officeRow}>
                <Body size={13.5} color={Colors.inkSecondary} style={{ flex: 1, lineHeight: 13.5 * 1.3 }}>{o.label}</Body>
                {o.period ? <Mono size={10} color={Colors.inkMuted}>{o.period}</Mono> : null}
              </View>
            ))}
            {offices.length > 10 ? (
              <Body size={12} color={Colors.inkMuted} style={{ marginTop: 8 }}>+ {offices.length - 10} flere hverv</Body>
            ) : null}
          </Section>
        ) : null}

        {/* Godser */}
        {estates.length ? (
          <Section title="Godser & besiddelser">
            <View style={styles.tagWrap}>
              {estates.map((e, i) => (
                <View key={i} style={styles.tag}>
                  <Serif size={16}>{e.navn}</Serif>
                  {e.period ? <Mono size={9.5} color={Colors.inkMuted} style={{ marginLeft: 6 }}>{e.period}</Mono> : null}
                </View>
              ))}
            </View>
          </Section>
        ) : null}

        {/* Materiale — galleri når billeder er tilknyttet, ellers tom-tilstand */}
        <Section title="Materiale">
          {gallery.length ? (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9 }}>
              {gallery.map(({ media: m, thumbUri }) => (
                <Pressable key={String(m.id)} onPress={() => setLightbox(lightboxItems.findIndex((x) => x.id === String(m.id)))}>
                  <SignedImage
                    uri={thumbUri}
                    style={{ width: 108, height: 108, borderRadius: 10, backgroundColor: Colors.surfaceSunken }}
                    contentFit="cover"
                    transition={150}
                  />
                </Pressable>
              ))}
            </ScrollView>
          ) : (
            <>
              <View style={{ flexDirection: 'row', gap: 9 }}>
                {['portræt', 'våben', 'dokument'].map((t) => (
                  <StripedPlaceholder key={t} label={t} style={{ flex: 1, aspectRatio: 1 }} />
                ))}
              </View>
              <Body size={11.5} color={Colors.inkMuted} style={{ marginTop: 8 }}>
                Billedmateriale tilknyttes efterhånden som det digitaliseres.
              </Body>
            </>
          )}
        </Section>

        {/* Kilder: alle udgavers poster (som web — vælgeren filtrerer ikke kilderne), nyeste udgave først. */}
        {sources.length ? (
          <Section title="Kilde i Aarbogen">
            {sources.map((s, i) => (
              <View key={i} style={styles.sourceRow}>
                <Serif size={18} color={Colors.bordeaux}>§</Serif>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <Body size={13.5} color={Colors.ink} style={{ fontFamily: Fonts.sansSemi, lineHeight: 13.5 * 1.25 }}>{s.work}</Body>
                  {s.ref ? <Mono size={10.5} color={Colors.inkMuted} style={{ marginTop: 2 }}>{s.ref}</Mono> : null}
                </View>
                <BtnLabel size={11} color={Colors.goldInk}>trykt værk</BtnLabel>
              </View>
            ))}
          </Section>
        ) : null}

        {/* Handlinger */}
        <View style={{ marginTop: 24, paddingHorizontal: 22, flexDirection: 'row', gap: 10 }}>
          <Pressable style={[styles.action, styles.actionSecondary]} onPress={() => { setFocus(person.id); router.push('/tree'); }}>
            <BtnLabel size={13} color={Colors.ink}>Vis i stamtræ</BtnLabel>
          </Pressable>
          <Pressable style={[styles.action, styles.actionPrimary]} onPress={() => { useStore.setState({ relA: person.id }); router.push('/relate'); }}>
            <BtnLabel size={13} color={Colors.inkOnInverse}>Slægtskab</BtnLabel>
          </Pressable>
        </View>
        {meId == null || isMe ? (
          <View style={{ marginTop: 10, paddingHorizontal: 22 }}>
            <Pressable style={[styles.meToggle, isMe && styles.meToggleActive]} onPress={() => setMe(isMe ? null : person.id)}>
              <BtnLabel size={13} color={isMe ? Colors.bordeaux : Colors.inkSecondary}>
                {isMe ? '★ Dette er dig — fjern markering' : 'Det er mig i slægten'}
              </BtnLabel>
            </Pressable>
          </View>
        ) : null}
      </ScrollView>
      {lightbox != null ? (
        <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
      ) : null}
    </View>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={{ marginTop: 22, paddingHorizontal: 22 }}>
      <Kicker size={9.5} style={{ marginBottom: 8, letterSpacing: 9.5 * 0.14 }}>{title}</Kicker>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  header: { paddingHorizontal: 22, paddingTop: 20, flexDirection: 'row', gap: 16, alignItems: 'flex-start' },
  badgeRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 10, alignItems: 'center' },
  badge: { borderRadius: 7, paddingHorizontal: 10, paddingVertical: 5 },
  badgeBordered: { borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light },
  udgaveRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 2, marginTop: 10, alignSelf: 'flex-start', backgroundColor: Colors.surfaceSunken, borderRadius: Radius.field, padding: 3 },
  udgaveChip: { borderRadius: 8, paddingHorizontal: 11, paddingVertical: 6 },
  udgaveChipActive: { backgroundColor: Colors.surfaceRaised },
  udgaveNote: { marginTop: 7, lineHeight: 11 * 1.45 },
  barnAf: {
    marginHorizontal: 22,
    marginTop: 18,
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: 7,
  },
  inlineItem: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  block: { marginHorizontal: 22, marginTop: 16 },
  childItem: { alignItems: 'center', width: 74 },
  childAvatar: {
    width: 50,
    height: 50,
    borderRadius: Radius.round,
    backgroundColor: Colors.surfaceSunken,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.faint,
    alignItems: 'center',
    justifyContent: 'center',
  },
  officeRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 12,
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.faint,
  },
  tagWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 7 },
  tag: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surfaceRaised,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: Border.light,
    borderRadius: 9,
    paddingHorizontal: 11,
    paddingVertical: 7,
  },
  sourceRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    paddingVertical: 11,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: Border.faint,
  },
  action: { flex: 1, borderRadius: Radius.field, paddingVertical: 13, alignItems: 'center' },
  actionPrimary: { backgroundColor: Colors.bordeaux },
  actionSecondary: { backgroundColor: Colors.surfaceSunken, borderWidth: StyleSheet.hairlineWidth, borderColor: Border.light },
  meToggle: { borderWidth: 1.5, borderColor: Border.medium, borderRadius: Radius.field, paddingVertical: 12, alignItems: 'center' },
  meToggleActive: { borderColor: Colors.bordeaux, backgroundColor: Colors.bordeauxTint },
});

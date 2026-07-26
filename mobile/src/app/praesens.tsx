// Præsensliste — redaktion-gated, lineær mobilvisning af slægtens nulevende medlemmer.
// Mobilens bevidste forskel fra web: ALLE navnetryk går direkte til personprofilen.
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { Image } from 'expo-image';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  buildPresensListe,
  groupByLinje,
  kanoniserPresensGrundlag,
  samlIds,
} from '@daa/core';
import type {
  PresensGren,
  PresensLinjeGruppe,
  PresensNode,
} from '@daa/core';
import { LoadGate } from '../components/LoadGate';
import { Body, BtnLabel, Kicker, Mono, Serif } from '../components/Typography';
import {
  fetchPresensGrundlag,
  fetchPresensNavneDele,
  formatAndetNavn,
  formatAnkerNavn,
  type PresensGrundlag,
  type PresensNavneDele,
} from '../data/presens';
import {
  fetchPresensIntro,
  fetchPresensLinjer,
  type PresensLinjeInfo,
} from '../data/presensLinjer';
import { useMediaAuthEpoch } from '../lib/media';
import type { Model } from '../data/types';
import { useStore } from '../store/useStore';
import { Border, Colors, Fonts, monoSpacing } from '../theme/tokens';

type Router = ReturnType<typeof useRouter>;

function PraesensNodeView({
  n,
  dybde,
  erAnker,
  model,
  router,
  navnAf,
  navnAfAnker,
}: {
  n: PresensNode;
  dybde: number;
  erAnker: boolean;
  model: Model | null;
  router: Router;
  navnAf: (id: string) => string;
  navnAfAnker: (id: string) => string;
}) {
  const aar = model?.byId[n.id]?.years ?? '';
  const partnere = n.partnere.filter((partner) => partner.levende || !n.forbindelsesled);

  // Børnene ligger i nestede Views. Derfor er marginLeft et FAST tillæg pr. niveau:
  // nestingen akkumulerer selv 16/32/48 px. dybde*16 her ville dobbelt-tælle forældrenes
  // forskydning og give voksende generationsafstand (web-regressionen fra 2026-07-24).
  return (
    <View style={{ marginLeft: dybde === 0 ? 0 : 16, marginBottom: 4 }}>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'baseline' }}>
        <Pressable onPress={() => router.push(`/person/${n.id}`)}>
          <Body
            size={13.5}
            color={n.forbindelsesled ? Colors.textMuted3 : Colors.ink}
            style={{
              fontFamily: n.forbindelsesled ? Fonts.sans : Fonts.sansSemi,
              fontStyle: n.forbindelsesled ? 'italic' : 'normal',
            }}
          >
            {erAnker ? navnAfAnker(n.id) : navnAf(n.id)}
          </Body>
        </Pressable>
        {aar ? <Mono size={10.5}> {aar}</Mono> : null}
        {n.usikker ? <Body size={12} color={Colors.gold}> ⚠</Body> : null}
        {n.krydsReference ? (
          <Body size={11.5} color={Colors.textMuted3}> ↗ vist andetsteds i denne gren</Body>
        ) : null}
      </View>

      {partnere.map((partner) => (
        <View
          key={partner.id}
          style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'baseline' }}
        >
          <Body size={12} color={Colors.textMuted3}>· g. m. </Body>
          <Pressable onPress={() => router.push(`/person/${partner.id}`)}>
            <Body size={12} color={Colors.textSecondary2}>
              {navnAf(partner.id)}
            </Body>
          </Pressable>
        </View>
      ))}

      {n.boern.map((barn) => (
        <PraesensNodeView
          key={barn.id}
          n={barn}
          dybde={dybde + 1}
          erAnker={false}
          model={model}
          router={router}
          navnAf={navnAf}
          navnAfAnker={navnAfAnker}
        />
      ))}
    </View>
  );
}

function PraesensGrenView({
  gren,
  model,
  router,
  navnAf,
  navnAfAnker,
}: {
  gren: PresensGren;
  model: Model | null;
  router: Router;
  navnAf: (id: string) => string;
  navnAfAnker: (id: string) => string;
}) {
  return (
    <View
      style={gren.anker.gren != null
        ? {
            marginTop: 28,
            borderLeftWidth: 2,
            borderLeftColor: 'rgba(185,160,106,0.45)',
            paddingLeft: 18,
          }
        : { marginTop: 22 }}
    >
      {gren.anker.gren != null ? (
        <Kicker size={10} color={Colors.gold} style={{ marginBottom: 5 }}>
          {gren.anker.gren}. gren
        </Kicker>
      ) : null}

      <PraesensNodeView
        n={gren.ankerBlok}
        dybde={0}
        erAnker
        model={model}
        router={router}
        navnAf={navnAf}
        navnAfAnker={navnAfAnker}
      />

      {gren.grupper.map((gruppe) => (
        <View key={`${gruppe.overskrift}-${gruppe.niveau}`} style={{ marginTop: 22 }}>
          <Kicker
            size={9.5}
            color={Colors.textSecondary2}
            style={{
              paddingBottom: 6,
              marginBottom: 8,
              borderBottomWidth: 1,
              borderBottomColor: Border.faint,
            }}
          >
            {gruppe.overskrift}{gruppe.usikker ? ' ⚠' : ''}
          </Kicker>
          {/* Gruppeoverskriften giver allerede konteksten: rødder starter på dybde 0. */}
          {gruppe.roedder.map((rod) => (
            <PraesensNodeView
              key={rod.id}
              n={rod}
              dybde={0}
              erAnker={false}
              model={model}
              router={router}
              navnAf={navnAf}
              navnAfAnker={navnAfAnker}
            />
          ))}
        </View>
      ))}
    </View>
  );
}

function PraesensLinjeSektion({
  gruppe,
  info,
  model,
  router,
  navnAf,
  navnAfAnker,
}: {
  gruppe: PresensLinjeGruppe;
  info: PresensLinjeInfo | undefined;
  model: Model | null;
  router: Router;
  navnAf: (id: string) => string;
  navnAfAnker: (id: string) => string;
}) {
  return (
    <View style={{ marginTop: 42 }}>
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          gap: 18,
          borderTopWidth: 1,
          borderTopColor: Border.medium,
          paddingTop: 22,
        }}
      >
        {info?.vaabenUrl ? (
          <Image
            source={{ uri: info.vaabenUrl }}
            accessibilityLabel="Linjens våben"
            contentFit="contain"
            style={{ width: 76, height: 100 }}
          />
        ) : null}
        <View style={{ flex: 1 }}>
          <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 8 }}>
            <Serif size={31} color={Colors.bordeaux}>{gruppe.linje}</Serif>
            <Kicker
              size={10.5}
              color={Colors.ink}
              style={{ letterSpacing: monoSpacing(10.5, 0.24) }}
            >
              linje
            </Kicker>
          </View>
          {info?.titel ? (
            <Serif
              size={18}
              italic
              color={Colors.textSecondary}
              style={{ marginTop: 5, lineHeight: 22 }}
            >
              {info.titel}
            </Serif>
          ) : null}
          {info?.slaegtsnavn ? (
            <Kicker
              size={9.5}
              color={Colors.textMuted2}
              style={{ marginTop: 5, letterSpacing: monoSpacing(9.5, 0.26) }}
            >
              {info.slaegtsnavn}
            </Kicker>
          ) : null}
        </View>
      </View>

      {gruppe.grene.map((gren) => (
        <PraesensGrenView
          key={gren.anker.personId}
          gren={gren}
          model={model}
          router={router}
          navnAf={navnAf}
          navnAfAnker={navnAfAnker}
        />
      ))}
    </View>
  );
}

export default function PraesensScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const rawModel = useStore((state) => state.model);
  // Mobil-storen holder canonicalIdById separat; sammenkoblingen skal bevares, så levende-flag
  // og ankre på samme_som-aliaser matcher den kollapsede graf.
  const canonicalIdById = useStore((state) => state.canonicalIdById);
  const model = useMemo(
    () => (rawModel ? { ...rawModel, canonicalIdById } : null),
    [rawModel, canonicalIdById],
  );
  const rolle = useStore((state) => state.rolle);
  const mediaAuthEpoch = useMediaAuthEpoch();
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [fejl, setFejl] = useState<string | null>(null);
  const [linjeInfo, setLinjeInfo] = useState<{
    epoch: number;
    values: Record<string, PresensLinjeInfo>;
  }>({ epoch: mediaAuthEpoch, values: {} });
  const synligLinjeInfo = linjeInfo.epoch === mediaAuthEpoch ? linjeInfo.values : {};
  const [intro, setIntro] = useState<string | null>(null);
  const [navneDele, setNavneDele] = useState<Record<string, PresensNavneDele>>({});

  useEffect(() => {
    let aktiv = true;
    if (rolle !== 'redaktion') {
      setLinjeInfo({ epoch: mediaAuthEpoch, values: {} });
      return () => { aktiv = false; };
    }
    setLinjeInfo({ epoch: mediaAuthEpoch, values: {} });
    fetchPresensGrundlag()
      .then((resultat) => {
        if (aktiv) {
          setGrundlag(resultat);
          setFejl(null);
        }
      })
      .catch((error) => {
        if (aktiv) setFejl(error instanceof Error ? error.message : String(error));
      });
    fetchPresensLinjer(mediaAuthEpoch)
      .then((resultat) => { if (aktiv) setLinjeInfo({ epoch: mediaAuthEpoch, values: resultat }); })
      .catch(() => { if (aktiv) setLinjeInfo({ epoch: mediaAuthEpoch, values: {} }); });
    fetchPresensIntro()
      .then((resultat) => { if (aktiv) setIntro(resultat); })
      .catch(() => { if (aktiv) setIntro(null); });
    return () => { aktiv = false; };
  }, [rolle, mediaAuthEpoch]);

  const liste = useMemo(() => {
    if (!model || !grundlag) return null;
    const kanonisk = kanoniserPresensGrundlag(
      model,
      grundlag.ankre,
      grundlag.levendeById,
    );
    return buildPresensListe(model, kanonisk.ankre, kanonisk.levendeById);
  }, [model, grundlag]);

  const linjer = useMemo(
    () => (liste ? groupByLinje(liste.grene) : []),
    [liste],
  );

  const alleIds = useMemo(() => {
    if (!liste) return [] as string[];
    const ids = new Set<string>();
    for (const gren of liste.grene) {
      samlIds(gren.ankerBlok, ids);
      for (const gruppe of gren.grupper) {
        for (const rod of gruppe.roedder) samlIds(rod, ids);
      }
    }
    return [...ids];
  }, [liste]);

  useEffect(() => {
    let aktiv = true;
    if (!alleIds.length) {
      return () => { aktiv = false; };
    }
    fetchPresensNavneDele(alleIds)
      .then((resultat) => { if (aktiv) setNavneDele(resultat); })
      .catch(() => { if (aktiv) setNavneDele({}); });
    return () => { aktiv = false; };
  }, [alleIds]);

  const fallbackNavn = (id: string) => model?.byId[id]?.name ?? `person ${id}`;
  const navnAf = (id: string) => formatAndetNavn(navneDele[id], fallbackNavn(id));
  const navnAfAnker = (id: string) =>
    formatAnkerNavn(navneDele[id], fallbackNavn(id));

  return (
    <LoadGate>
      <ScrollView
        style={{ flex: 1, backgroundColor: Colors.paperBg }}
        contentContainerStyle={{
          paddingTop: insets.top + 12,
          paddingHorizontal: 14,
          paddingBottom: 42,
        }}
      >
        {rolle !== 'redaktion' ? (
          <View style={{ marginTop: 24, paddingHorizontal: 4 }}>
            <Body size={13} color={Colors.textSecondary2}>
              Præsenslisten kræver redaktør-login (v1 er redaktion-only).
            </Body>
            <Pressable onPress={() => router.push('/konto')} style={{ marginTop: 12 }}>
              <BtnLabel size={13} color={Colors.bordeaux}>Log ind ›</BtnLabel>
            </Pressable>
          </View>
        ) : fejl ? (
          <Body size={13} color={Colors.bordeaux} style={{ marginTop: 24 }}>
            Kunne ikke hente grundlaget: {fejl}
          </Body>
        ) : !liste ? (
          <Body size={13} color={Colors.textSecondary2} style={{ marginTop: 24 }}>
            Henter…
          </Body>
        ) : liste.grene.length === 0 ? (
          <View style={{ marginTop: 24, paddingHorizontal: 4 }}>
            <Body size={13} color={Colors.textSecondary2}>
              Ingen overhoveder udpeget endnu. Udpeg et linje-/gren-overhoved via person-editorens
              felt &quot;Overhoved (linje/gren)&quot; (værdi fx &quot;II linje, 1. gren&quot;).
            </Body>
            {Object.values(grundlag?.levendeById ?? {}).every((value) => !value) ? (
              <Body size={12} color={Colors.textMuted3} style={{ marginTop: 10 }}>
                Bemærk: modellen indeholder ingen levende personer — er du logget ind som redaktør,
                så genindlæs appen, så data hentes med dit login.
              </Body>
            ) : null}
          </View>
        ) : (
          <View
            style={{
              backgroundColor: Colors.paperCard,
              borderWidth: 1,
              borderColor: Border.light,
              borderRadius: 4,
              paddingHorizontal: 20,
              paddingVertical: 38,
            }}
          >
            <View style={{ alignItems: 'center' }}>
              <Kicker size={9.5} color={Colors.textMuted2}>Slægten Reventlow</Kicker>
              <Serif size={36} style={{ marginTop: 9, lineHeight: 39 }}>Præsensliste</Serif>
              <Body
                size={12.5}
                color={Colors.textMuted}
                style={{ marginTop: 8, textAlign: 'center' }}
              >
                Slægtens nulevende medlemmer, ordnet efter linje og gren
              </Body>
              <View
                style={{
                  width: 42,
                  height: 1.5,
                  backgroundColor: Colors.gold,
                  marginTop: 22,
                }}
              />
            </View>

            {intro ? (
              <View style={{ marginTop: 28 }}>
                {intro.split(/\n\s*\n/).map((afsnit, index) => (
                  <Serif
                    key={`${index}-${afsnit.slice(0, 20)}`}
                    size={16.5}
                    italic
                    color={Colors.textSecondary}
                    style={{ lineHeight: 25, marginTop: index === 0 ? 0 : 14 }}
                  >
                    {afsnit}
                  </Serif>
                ))}
              </View>
            ) : null}

            {liste.advarsler.length > 0 ? (
              <Body
                size={10.5}
                color={Colors.textMuted3}
                style={{
                  marginTop: 24,
                  paddingBottom: 10,
                  borderBottomWidth: 1,
                  borderBottomColor: Border.faint,
                }}
              >
                {liste.advarsler.length} redaktionelle advarsler
                {' '}— rapportering, udløser aldrig ændringer
              </Body>
            ) : null}

            {linjer.map((linje) => (
              <PraesensLinjeSektion
                key={linje.linje}
                gruppe={linje}
                info={synligLinjeInfo[linje.linje]}
                model={model}
                router={router}
                navnAf={navnAf}
                navnAfAnker={navnAfAnker}
              />
            ))}

            <Mono
              size={9.5}
              color={Colors.textMuted2}
              style={{
                marginTop: 42,
                paddingTop: 12,
                borderTopWidth: 1,
                borderTopColor: Border.faint,
                textAlign: 'center',
              }}
            >
              Kun levende personer samt afdøde forbindelsesled medtages.
            </Mono>
          </View>
        )}
      </ScrollView>
    </LoadGate>
  );
}

// Præsensliste (spec 2026-07-22 §6) — redaktion-gated læsevisning, spejler webbens PresensView.
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { buildPresensListe, kanoniserPresensGrundlag } from '@daa/core';
import type { PresensGren, PresensNode } from '@daa/core';
import { LoadGate } from '../components/LoadGate';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { fetchPresensGrundlag, type PresensGrundlag } from '../data/presens';
import type { Model } from '../data/types';
import { useStore } from '../store/useStore';
import { Border, Colors } from '../theme/tokens';

// Modul-scope (ikke indlejret i skærmen): bevarer komponent-identitet på tværs af re-renders —
// en indlejret komponent ville genoprettes ved hvert render og tvinge fuld remount af hele træet.
function PraesensNodeView({ n, dybde, model, router }: {
  n: PresensNode; dybde: number; model: Model | null; router: ReturnType<typeof useRouter>;
}) {
  const person = model?.byId[n.id];
  const navn = person?.name ?? `person ${n.id}`;
  const aar = person?.years ? ` ${person.years}` : '';
  // Kun levende partnere vises for et forbindelsesled (afdød) — spejler webbens PresensGrenSektion.
  const partnere = n.partnere.filter((p) => p.levende || !n.forbindelsesled);
  return (
    <View style={{ marginLeft: dybde * 16, marginBottom: 4 }}>
      <Pressable onPress={() => router.push(`/person/${n.id}`)}>
        <Body
          size={13}
          color={n.forbindelsesled ? Colors.textMuted3 : Colors.ink}
          style={{ fontStyle: n.forbindelsesled ? 'italic' : 'normal' }}
        >
          {navn}{aar}{n.usikker ? ' ⚠' : ''}
        </Body>
      </Pressable>
      {partnere.map((p) => {
        const pPerson = model?.byId[p.id];
        return (
          <Pressable key={p.id} onPress={() => router.push(`/person/${p.id}`)}>
            <Body size={12} color={Colors.textMuted3}>
              {'  '}· g. m. {pPerson?.name ?? `person ${p.id}`}
            </Body>
          </Pressable>
        );
      })}
      {n.boern.map((barn) => <PraesensNodeView key={barn.id} n={barn} dybde={dybde + 1} model={model} router={router} />)}
    </View>
  );
}

function PraesensGrenView({ gren, model, router }: {
  gren: PresensGren; model: Model | null; router: ReturnType<typeof useRouter>;
}) {
  return (
    <View style={{ marginBottom: 30 }}>
      <BtnLabel
        size={13}
        color={Colors.bordeaux}
        style={{ textTransform: 'uppercase', letterSpacing: 1.5, marginBottom: 10 }}
      >
        {gren.anker.raaVaerdi}
      </BtnLabel>
      <PraesensNodeView n={gren.ankerBlok} dybde={0} model={model} router={router} />
      {gren.grupper.map((gruppe) => (
        <View key={`${gruppe.overskrift}-${gruppe.niveau}`} style={{ marginTop: 14 }}>
          <BtnLabel
            size={11.5}
            color={Colors.textMuted3}
            style={{ textTransform: 'uppercase', letterSpacing: 2, marginBottom: 5 }}
          >
            {gruppe.overskrift}{gruppe.usikker ? ' ⚠' : ''}
          </BtnLabel>
          {gruppe.roedder.map((rod) => <PraesensNodeView key={rod.id} n={rod} dybde={1} model={model} router={router} />)}
        </View>
      ))}
    </View>
  );
}

export default function PraesensScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const model = useStore((s) => s.model);
  const rolle = useStore((s) => s.rolle);
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [fejl, setFejl] = useState<string | null>(null);

  useEffect(() => {
    let aktiv = true;
    if (rolle !== 'redaktion') {
      setGrundlag(null);
      setFejl(null);
      return () => { aktiv = false; };
    }
    setFejl(null);
    fetchPresensGrundlag()
      .then((resultat) => { if (aktiv) setGrundlag(resultat); })
      .catch((e) => { if (aktiv) setFejl(e instanceof Error ? e.message : String(e)); });
    return () => { aktiv = false; };
  }, [rolle]);

  const liste = useMemo(() => {
    if (!model || !grundlag) return null;
    const kanonisk = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, kanonisk.ankre, kanonisk.levendeById);
  }, [model, grundlag]);

  return (
    <LoadGate>
      <ScrollView
        style={{ flex: 1, backgroundColor: Colors.paperBg }}
        contentContainerStyle={{ paddingTop: insets.top + 12, paddingHorizontal: 18, paddingBottom: 30 }}
      >
        {rolle !== 'redaktion' ? (
          <View style={{ marginTop: 24 }}>
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
          <View style={{ marginTop: 24 }}>
            <Body size={13} color={Colors.textSecondary2}>
              Ingen overhoveder udpeget endnu. Udpeg et linje-/gren-overhoved via person-editorens
              felt &quot;Overhoved (linje/gren)&quot; (værdi fx &quot;II linje, 1. gren&quot;).
            </Body>
            {Object.values(grundlag?.levendeById ?? {}).every((v) => !v) ? (
              <Body size={12} color={Colors.textMuted3} style={{ marginTop: 10 }}>
                Bemærk: modellen indeholder ingen levende personer — er du logget ind som redaktør,
                så genindlæs appen, så data hentes med dit login.
              </Body>
            ) : null}
          </View>
        ) : (
          <>
            <Serif size={24} style={{ marginBottom: 16 }}>Præsensliste</Serif>
            {liste.advarsler.length > 0 ? (
              <Body
                size={11.5}
                color={Colors.textMuted3}
                style={{ marginBottom: 18, paddingBottom: 12, borderBottomWidth: 1, borderBottomColor: Border.faint }}
              >
                {liste.advarsler.length} redaktionelle advarsler (rapportering — udløser aldrig ændringer)
              </Body>
            ) : null}
            {liste.grene.map((gren) => <PraesensGrenView key={gren.anker.personId} gren={gren} model={model} router={router} />)}
          </>
        )}
      </ScrollView>
    </LoadGate>
  );
}

// Narrativ-editor (udgave-faner + tekstfelt + billed/link-indsættelse + forhåndsvisning) —
// selvstændig komponent (billeder-i-narrativer 2026-07-05, Slice C3), generaliseret fra person-
// editorens tidligere ENKELT-udgave-tilstand til ALLE udgaver af ethvert subjekt
// ('person'|'slaegt'|'lineage'). Ejer sin egen tilstand og eget skrive-flow (SkrivePreviewSheet)
// — kan droppes ind i person-editoren OG den nye slægts/linje-editor uden prop-drilling af parent-
// state, i modsætning til web's Redaktion.tsx (der løftede tilstanden til den store container-
// komponent; mobile har ingen tilsvarende ét-komponent-container at løfte ind i).
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Switch, TextInput, View } from 'react-native';
import { NarrativRenderer } from '../NarrativRenderer';
import { MediaMentionPicker } from './MediaMentionPicker';
import { MentionPicker } from './MentionPicker';
import { SkrivePreviewSheet } from './SkrivePreviewSheet';
import { Body, BtnLabel, Mono } from '../Typography';
import { Border, Colors, Radius } from '../../theme/tokens';
import { insertAt } from '@daa/core';
import { fetchNarrativer, fetchSources, type PersonNarrativ, type SourceRow, type PersonMedia } from '../../data/redaktionRead';
import { type Change } from '../../data/redaktionWrite';

export function NarrativEditor({ subjektType, subjektId, media, mediaThumbUris }: {
  subjektType: string;
  subjektId: string;
  media: PersonMedia[];
  mediaThumbUris: Record<string, string>;
}) {
  const [narrativer, setNarrativer] = useState<PersonNarrativ[]>([]);
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [aktivSourceId, setAktivSourceId] = useState<number | null>(null);
  const [udkast, setUdkast] = useState({ tekst: '', privat: false, side: '' });
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading');
  const [nyUdgave, setNyUdgave] = useState<{ titel: string; udgave: string } | null>(null);
  const [pending, setPending] = useState<Change | null>(null);
  const selPos = useRef(0);
  const [mentionPickerÅben, setMentionPickerÅben] = useState(false);
  const [mediaMentionPickerÅben, setMediaMentionPickerÅben] = useState(false);

  const indlæs = useCallback(() => {
    setStatus('loading');
    fetchNarrativer(subjektType, Number(subjektId)).then((ns) => {
      setNarrativer(ns);
      const first = ns[0];
      setAktivSourceId(first?.sourceId ?? 1);
      setUdkast({ tekst: first?.tekst ?? '', privat: first?.privat ?? false, side: first?.side ?? '' });
      setStatus('ready');
    }).catch(() => setStatus('error'));
  }, [subjektType, subjektId]);
  useEffect(indlæs, [indlæs]);
  useEffect(() => { fetchSources().then(setSources).catch(() => setSources([])); }, []);

  const vaelgUdgave = (sourceId: number | null) => {
    setAktivSourceId(sourceId); setNyUdgave(null);
    const n = narrativer.find((x) => x.sourceId === sourceId) ?? null;
    setUdkast({ tekst: n?.tekst ?? '', privat: n?.privat ?? false, side: n?.side ?? '' });
  };
  const ledigeSources = sources.filter((s) => !narrativer.some((n) => n.sourceId === s.id));

  return (
    <View style={styles.sektion}>
      <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 6 }}>Narrativ / biografi</Mono>
      {status === 'error' ? (
        <Mono size={11} color={Colors.liveRoed}>Kunne ikke hente narrativ. Genindlæs.</Mono>
      ) : (
        <>
          {/* Udgave-faner: én pr. kilde subjektet har en narrativ i, + evt. ny (ugemt) udgave + "+ Ny udgave" */}
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginBottom: 10 }}>
            {narrativer.map((n) => {
              const aktiv = n.sourceId === aktivSourceId;
              return (
                <Pressable key={n.id} onPress={() => vaelgUdgave(n.sourceId)}
                  style={[styles.fane, aktiv && styles.faneAktiv]}>
                  <Mono size={10.5} color={aktiv ? '#fff' : Colors.textMuted}>
                    {(n.udgave ?? n.sourceTitel ?? `Kilde ${n.sourceId ?? '—'}`) + (n.privat ? ' · privat' : '')}
                  </Mono>
                </Pressable>
              );
            })}
            {aktivSourceId != null && !narrativer.some((n) => n.sourceId === aktivSourceId) && (
              <View style={[styles.fane, styles.faneAktiv]}>
                <Mono size={10.5} color="#fff">{(sources.find((s) => s.id === aktivSourceId)?.udgave ?? `Kilde ${aktivSourceId}`) + ' · ny'}</Mono>
              </View>
            )}
            <Pressable onPress={() => setNyUdgave({ titel: '', udgave: '' })} style={styles.faneNy}>
              <Mono size={10.5} color={Colors.textMuted2}>+ Ny udgave</Mono>
            </Pressable>
          </View>

          {nyUdgave != null && (
            <View style={styles.nyUdgaveBoks}>
              <Mono size={9.5} color={Colors.textMuted}>Vælg en udgave subjektet ikke har endnu:</Mono>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 4 }}>
                {ledigeSources.map((s) => (
                  <Pressable key={s.id} onPress={() => vaelgUdgave(s.id)} style={styles.faneNy}>
                    <Mono size={10.5} color={Colors.textMuted}>{s.udgave ?? s.titel ?? `Kilde ${s.id}`}</Mono>
                  </Pressable>
                ))}
                {ledigeSources.length === 0 && <Mono size={10} color={Colors.textMuted2}>(ingen ledige)</Mono>}
              </View>
              <Mono size={9.5} color={Colors.textMuted} style={{ marginTop: 8 }}>… eller opret en ny DAA-udgave:</Mono>
              <TextInput value={nyUdgave.titel} onChangeText={(v) => setNyUdgave((u) => ({ ...u!, titel: v }))}
                placeholder="Titel" placeholderTextColor={Colors.textMuted2} style={styles.nyUdgaveInput} />
              <TextInput value={nyUdgave.udgave} onChangeText={(v) => setNyUdgave((u) => ({ ...u!, udgave: v }))}
                placeholder="Udgave (DAA 1982-84)" placeholderTextColor={Colors.textMuted2} style={styles.nyUdgaveInput} />
              <Pressable style={styles.nyUdgaveOpretKnap}
                onPress={() => {
                  if (!nyUdgave.titel.trim()) return;
                  setPending({ art: 'opretKilde', subjektType: 'source', subjektId: '',
                    payload: { titel: nyUdgave.titel.trim(), slags: 'DAA-udgave', udgave: nyUdgave.udgave.trim() || null } });
                }}>
                <BtnLabel size={12} color="#fff">Opret</BtnLabel>
              </Pressable>
            </View>
          )}

          <View style={{ flexDirection: 'row', gap: 16, marginBottom: 6 }}>
            <Pressable disabled={status !== 'ready'} onPress={() => setMentionPickerÅben(true)}>
              <BtnLabel size={12.5} color={Colors.bordeaux}>🔗 Indsæt link</BtnLabel>
            </Pressable>
            <Pressable disabled={status !== 'ready'} onPress={() => setMediaMentionPickerÅben(true)}>
              <BtnLabel size={12.5} color={Colors.bordeaux}>🖼 Indsæt billede</BtnLabel>
            </Pressable>
          </View>
          <TextInput
            multiline
            editable={status === 'ready'}
            value={udkast.tekst}
            onChangeText={(v) => setUdkast((u) => ({ ...u, tekst: v }))}
            onSelectionChange={(e) => { selPos.current = e.nativeEvent.selection.start; }}
            style={styles.input}
            placeholder={status === 'loading' ? 'Henter…' : 'Skriv biografi her…'}
            placeholderTextColor={Colors.textMuted2}
            textAlignVertical="top"
          />
          {/* Passiv forhåndsvisning — samme rolle som web's (review 12-mønster): viser hvordan
              [[type:id|tekst]]-tokens renderes for publikum, uden at gøre den selv klikbar. */}
          {!!udkast.tekst && (
            <View style={styles.previewBoks}>
              <Mono size={9} color={Colors.textMuted2} style={{ marginBottom: 4 }}>SÅDAN VISES DET FOR BESØGENDE</Mono>
              <NarrativRenderer tekst={udkast.tekst} size={12.5} color={Colors.textMuted} />
            </View>
          )}
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 9 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <Switch value={udkast.privat} onValueChange={(v) => setUdkast((u) => ({ ...u, privat: v }))}
                thumbColor={udkast.privat ? Colors.bordeaux : Colors.textMuted2} trackColor={{ false: Colors.beige3, true: Colors.bordeauxFillLight2 }} />
              <Body size={11} color={Colors.textMuted}>privat</Body>
            </View>
            <TextInput value={udkast.side} onChangeText={(v) => setUdkast((u) => ({ ...u, side: v }))}
              placeholder="side, fx 209-211" placeholderTextColor={Colors.textMuted2} style={styles.sideInput} />
          </View>
          <Pressable
            style={[styles.gemKnap, status !== 'ready' && { opacity: 0.5 }]}
            disabled={status !== 'ready'}
            onPress={() => setPending({ art: 'narrativ', subjektType, subjektId, vaerdi: udkast.tekst,
              payload: { privat: udkast.privat, sourceId: aktivSourceId, side: udkast.side.trim() || null } })}
          >
            <BtnLabel color="#fff">Gem narrativ</BtnLabel>
          </Pressable>

          {mentionPickerÅben ? (
            <MentionPicker
              onClose={() => setMentionPickerÅben(false)}
              onVælg={(token) => {
                const r = insertAt(udkast.tekst, selPos.current, token);
                setUdkast((u) => ({ ...u, tekst: r.text }));
                selPos.current = r.cursor;
              }}
            />
          ) : null}
          {mediaMentionPickerÅben ? (
            <MediaMentionPicker
              media={media.filter((m) => m.uploadStatus === 'klar')}
              thumbUris={mediaThumbUris}
              onClose={() => setMediaMentionPickerÅben(false)}
              onVælg={(token) => {
                const r = insertAt(udkast.tekst, selPos.current, token);
                setUdkast((u) => ({ ...u, tekst: r.text }));
                selPos.current = r.cursor;
              }}
            />
          ) : null}
        </>
      )}
      <SkrivePreviewSheet
        change={pending}
        onClose={() => setPending(null)}
        onApplied={(result) => {
          const art = pending?.art;
          setPending(null);
          if (art === 'opretKilde' && result != null) {
            // Ny udgave oprettet LIVE: brug den straks som aktiv (ugemt) fane, som web's opretUdgave.
            fetchSources().then(setSources).catch(() => {});
            setNyUdgave(null);
            setAktivSourceId(Number(result));
            setUdkast({ tekst: '', privat: false, side: '' });
          } else if (art === 'narrativ') {
            indlæs();
          }
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  sektion: { marginTop: 20, paddingTop: 16, borderTopWidth: 1, borderTopColor: Border.light },
  fane: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 7, borderWidth: 1, borderColor: Border.medium },
  faneAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  faneNy: { paddingVertical: 5, paddingHorizontal: 10, borderRadius: 7, borderWidth: 1, borderStyle: 'dashed', borderColor: Border.medium },
  nyUdgaveBoks: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field, padding: 10, marginBottom: 10 },
  nyUdgaveInput: { backgroundColor: '#fff', borderWidth: 1, borderColor: Border.light, borderRadius: 6, paddingHorizontal: 9, paddingVertical: 6, marginTop: 6, fontFamily: 'HankenGrotesk_400Regular', fontSize: 12.5, color: Colors.ink },
  nyUdgaveOpretKnap: { backgroundColor: Colors.bordeaux, borderRadius: 6, paddingVertical: 8, alignItems: 'center', marginTop: 8 },
  input: { backgroundColor: Colors.paperCard, borderRadius: Radius.field, borderWidth: 1, borderColor: Border.medium, padding: 12, minHeight: 120, fontFamily: 'HankenGrotesk_400Regular', fontSize: 13, color: Colors.ink },
  previewBoks: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: Radius.field, padding: 10, marginTop: 8 },
  sideInput: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light, borderRadius: 6, paddingHorizontal: 8, paddingVertical: 5, fontFamily: 'HankenGrotesk_400Regular', fontSize: 11, color: Colors.ink, minWidth: 110 },
  gemKnap: { backgroundColor: Colors.bordeaux, borderRadius: Radius.field, padding: 14, alignItems: 'center', marginTop: 10 },
});

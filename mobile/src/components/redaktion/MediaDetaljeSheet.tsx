import { Image } from 'expo-image';
import { useEffect, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, TextInput, View } from 'react-native';
import { Body, BtnLabel, Mono, Serif } from '../Typography';
import { Lightbox } from '../Lightbox';
import type { MediaAnvendelse, PersonMedia, UdrensPreview } from '../../data/redaktionRead';
import { Border, Colors, Radius } from '../../theme/tokens';

const MEDIA_SLAGS = ['foto', 'maleri', 'portræt', 'segl', 'dokument'] as const;
const RETTIGHED_STATUS = ['ukendt', 'public_domain', 'licenseret', 'tilladelse_givet', 'begraenset', 'spaerret'] as const;

type DetaljeMedia = Omit<PersonMedia, 'relationId'> & { relationId?: string };

export function MediaDetaljeSheet({ media, uri, thumbUri, anvendelse, anvendelseFejl, onClose, onGemMetadata, onGemRettigheder, onFjern, onFjernTilknytning, onTilknyt, onSlet, onGenopret, onErstatFil, onUdrens, udrensPreview, onSaetPortraet }: {
  media: DetaljeMedia;
  uri?: string;
  thumbUri?: string;
  anvendelse?: MediaAnvendelse;
  anvendelseFejl?: string;
  onClose: () => void;
  onGemMetadata: (payload: Record<string, unknown>) => void;
  onGemRettigheder: (payload: Record<string, unknown>) => void;
  onFjern: () => void;
  onFjernTilknytning?: (relationId: string) => void;
  onTilknyt?: () => void;
  onSlet: () => void;
  onGenopret: () => void;
  onErstatFil?: () => void | Promise<unknown>;
  onUdrens?: () => void | Promise<unknown>;
  udrensPreview?: UdrensPreview;
  onSaetPortraet?: (personId: string, mediaId: string | null) => void | Promise<unknown>;
}) {
  const [meta, setMeta] = useState({ titel: '', slags: 'foto', kunstner: '', datering: '' });
  const [ret, setRet] = useState({ status: 'ukendt', maaPubliceres: false, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
  const [lightbox, setLightbox] = useState(false);
  const [bekraeftSlet, setBekraeftSlet] = useState(false);
  const [bekraeftUdrens, setBekraeftUdrens] = useState(false);
  const [medieAktionBusy, setMedieAktionBusy] = useState(false);
  const medieAktionBusyRef = useRef(false);
  useEffect(() => {
    setMeta({ titel: media.titel ?? '', slags: media.slags || 'foto', kunstner: media.kunstner ?? '', datering: media.datering ?? '' });
    setRet({ status: media.rettighederStatus || 'ukendt', maaPubliceres: media.maaPubliceres, licens: '', kildehenvisning: '', gengivelsestilladelse: '', kildeFritekst: '' });
    setBekraeftSlet(false);
    setBekraeftUdrens(false);
    setMedieAktionBusy(false);
    medieAktionBusyRef.current = false;
  }, [media.id, media.titel, media.slags, media.kunstner, media.datering, media.rettighederStatus, media.maaPubliceres]);

  async function runMedieAktion(action: () => void | Promise<unknown>, holdUntilUnmount = false) {
    if (medieAktionBusyRef.current) return;
    medieAktionBusyRef.current = true;
    setMedieAktionBusy(true);
    try {
      await action();
    } finally {
      if (!holdUntilUnmount) {
        medieAktionBusyRef.current = false;
        setMedieAktionBusy(false);
      }
    }
  }

  const metadataPayload: Record<string, unknown> = {};
  if (meta.titel !== (media.titel ?? '')) metadataPayload.titel = meta.titel.trim();
  if (meta.slags !== media.slags) metadataPayload.slags = meta.slags;
  if (meta.kunstner !== (media.kunstner ?? '')) metadataPayload.kunstner = meta.kunstner.trim();
  if (meta.datering !== (media.datering ?? '')) metadataPayload.datering = meta.datering.trim();
  const mediaSlags = Array.from(new Set<string>([...MEDIA_SLAGS, meta.slags].filter(Boolean)));
  const warning = ret.maaPubliceres && (ret.status === 'spaerret' || ret.status === 'begraenset');
  const filinfo = [media.mimeType, media.bredde && media.hoejde ? `${media.bredde}×${media.hoejde}` : null,
    media.byteSize != null ? `${Math.round(media.byteSize / 1024)} KB` : null, media.originalFilnavn].filter(Boolean).join(' · ');
  const erBillede = media.mimeType?.startsWith('image/') === true && !!thumbUri && !!uri;
  const antalAfbildet = anvendelse?.afbildet.length ?? 0;
  const antalMentions = anvendelse?.mentions.length ?? 0;
  const erIBrug = antalAfbildet + antalMentions > 0;
  const sletAdvarsel = `Bruges på ${antalAfbildet} ${antalAfbildet === 1 ? 'tilknytning' : 'tilknytninger'} og i ${antalMentions} ${antalMentions === 1 ? 'narrativ' : 'narrativer'} — slet alligevel? Mentions bliver stående som inaktive tokens.`;

  return (
    <Modal visible transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} />
      <View style={styles.sheet}>
        <ScrollView contentContainerStyle={{ padding: 20, paddingBottom: 38 }} keyboardShouldPersistTaps="handled">
          <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 10 }}>
            <Serif size={22} style={{ flex: 1 }}>{media.titel || 'Medie'}</Serif>
            <Pressable onPress={onClose}><Serif size={24} color={Colors.textMuted}>×</Serif></Pressable>
          </View>
          {erBillede ? (
            <Pressable disabled={media.uploadStatus !== 'klar'} onPress={() => setLightbox(true)}>
              <Image source={{ uri: uri! }} style={[styles.preview, media.uploadStatus === 'fjernet' && { opacity: .5 }]} contentFit="contain" />
            </Pressable>
          ) : <View style={[styles.preview, styles.dokument, media.uploadStatus === 'fjernet' && { opacity: .5 }]}>
            <Serif size={32} color={Colors.textMuted}>▤</Serif><Body size={12} color={Colors.textMuted}>{media.slags || 'dokument'}</Body>
          </View>}
          <Mono size={8.5} color={Colors.textMuted2} style={{ marginTop: 5 }}>{media.uploadStatus} · {filinfo || 'ingen filmetadata'}</Mono>

          <Mono size={9} color={Colors.gold} style={styles.heading}>METADATA</Mono>
          <View style={styles.chips}>{mediaSlags.map((s) => (
            <Pressable key={s} style={[styles.chip, meta.slags === s && styles.chipAktiv]} onPress={() => setMeta((m) => ({ ...m, slags: s }))}>
              <BtnLabel size={10.5} color={meta.slags === s ? '#fff' : Colors.textSecondary2}>{s}</BtnLabel>
            </Pressable>
          ))}</View>
          <TextInput style={styles.input} placeholder="Titel" placeholderTextColor={Colors.textMuted2} value={meta.titel} onChangeText={(v) => setMeta((m) => ({ ...m, titel: v }))} />
          <TextInput style={styles.input} placeholder="Kunstner" placeholderTextColor={Colors.textMuted2} value={meta.kunstner} onChangeText={(v) => setMeta((m) => ({ ...m, kunstner: v }))} />
          <TextInput style={styles.input} placeholder="Datering" placeholderTextColor={Colors.textMuted2} value={meta.datering} onChangeText={(v) => setMeta((m) => ({ ...m, datering: v }))} />
          <Pressable disabled={!Object.keys(metadataPayload).length} style={[styles.gem, !Object.keys(metadataPayload).length && { opacity: .45 }]} onPress={() => onGemMetadata(metadataPayload)}>
            <BtnLabel color="#fff">Gem metadata</BtnLabel>
          </Pressable>

          <Mono size={9} color={Colors.gold} style={styles.heading}>RETTIGHEDER OG PUBLICERING</Mono>
          <View style={styles.chips}>{RETTIGHED_STATUS.map((s) => (
            <Pressable key={s} style={[styles.chip, ret.status === s && styles.chipAktiv]} onPress={() => setRet((r) => ({ ...r, status: s }))}>
              <BtnLabel size={9.5} color={ret.status === s ? '#fff' : Colors.textSecondary2}>{s}</BtnLabel>
            </Pressable>
          ))}</View>
          <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 10 }}>
            <Body size={13} style={{ flex: 1 }}>Må publiceres</Body>
            <Switch value={ret.maaPubliceres} onValueChange={(v) => setRet((r) => ({ ...r, maaPubliceres: v }))}
              thumbColor={ret.maaPubliceres ? Colors.bordeaux : Colors.textMuted2}
              trackColor={{ false: Colors.beige3, true: Colors.bordeauxFillLight2 }} />
          </View>
          {warning ? <Mono size={9.5} color={Colors.danger} style={{ marginTop: 6 }}>Advarsel: {ret.status} og publicering er valgt samtidig.</Mono> : null}
          <TextInput style={styles.input} placeholder="Licens" placeholderTextColor={Colors.textMuted2} value={ret.licens} onChangeText={(v) => setRet((r) => ({ ...r, licens: v }))} />
          <TextInput style={styles.input} placeholder="Kildehenvisning" placeholderTextColor={Colors.textMuted2} value={ret.kildehenvisning} onChangeText={(v) => setRet((r) => ({ ...r, kildehenvisning: v }))} />
          <TextInput style={styles.input} placeholder="Gengivelsestilladelse" placeholderTextColor={Colors.textMuted2} value={ret.gengivelsestilladelse} onChangeText={(v) => setRet((r) => ({ ...r, gengivelsestilladelse: v }))} />
          <TextInput style={styles.input} placeholder="Kildenote" placeholderTextColor={Colors.textMuted2} value={ret.kildeFritekst} onChangeText={(v) => setRet((r) => ({ ...r, kildeFritekst: v }))} />
          <Pressable style={styles.gem} onPress={() => onGemRettigheder(ret)}><BtnLabel color="#fff">Gem rettigheder</BtnLabel></Pressable>

          <View style={styles.anvendelseHeader}>
            <Mono size={9} color={Colors.gold}>BRUGES PÅ</Mono>
            {onTilknyt ? <Pressable disabled={!anvendelse} style={[styles.neutral, !anvendelse && { opacity: .45 }]} onPress={onTilknyt}><BtnLabel size={10} color={Colors.bordeaux}>Tilknyt til…</BtnLabel></Pressable> : null}
          </View>
          {!anvendelse ? <Body size={12} color={anvendelseFejl ? Colors.danger : Colors.textMuted}>{anvendelseFejl || 'Henter anvendelser…'}</Body> : <View style={{ gap: 7 }}>
            {anvendelse.afbildet.map((a) => <View key={a.relationId} style={styles.anvendelseRad}>
              <Body size={12.5} style={{ flex: 1 }}>{a.navn} · {a.type}</Body>
              {a.primaer ? <Mono size={8.5} color={Colors.gold}>Portræt</Mono> : null}
              {a.type === 'person' && media.uploadStatus === 'klar' && onSaetPortraet ? (
                <Pressable disabled={medieAktionBusy} onPress={() => {
                  void runMedieAktion(() => onSaetPortraet(a.id, a.primaer ? null : media.id), true);
                }}>
                  <BtnLabel size={10} color={Colors.bordeaux}>
                    {a.primaer ? 'Fjern portræt-valg' : 'Sæt som portræt'}
                  </BtnLabel>
                </Pressable>
              ) : null}
              {onFjernTilknytning ? <Pressable onPress={() => onFjernTilknytning(a.relationId)}><BtnLabel size={10} color={Colors.danger}>Fjern</BtnLabel></Pressable> : null}
            </View>)}
            {anvendelse.mentions.map((m) => <View key={`${m.kildeType}:${m.kildeId}`} style={styles.anvendelseRad}>
              <Body size={12.5}>{m.kildeType === 'narrative' ? 'Narrativ' : m.kildeType} på {m.subjektNavn}</Body>
            </View>)}
            {!erIBrug ? <Body size={12} color={Colors.textMuted}>Mediet bruges ikke endnu.</Body> : null}
          </View>}

          <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'flex-end', gap: 8, marginTop: 22 }}>
            {media.uploadStatus === 'fjernet' ? (
              <>
                <Pressable style={styles.gem} onPress={onGenopret}><BtnLabel color="#fff">Genopret</BtnLabel></Pressable>
                {onUdrens ? <Pressable
                  disabled={medieAktionBusy || !udrensPreview?.kanUdrenses}
                  style={[styles.slet, (medieAktionBusy || !udrensPreview?.kanUdrenses) && { opacity: .45 }]}
                  onPress={() => {
                    if (medieAktionBusyRef.current || !udrensPreview?.kanUdrenses) return;
                    if (!bekraeftUdrens) { setBekraeftUdrens(true); return; }
                    void runMedieAktion(onUdrens, true);
                  }}>
                  <BtnLabel size={bekraeftUdrens ? 9 : undefined} color="#fff">
                    {medieAktionBusy ? 'Sletter permanent…' : bekraeftUdrens
                      ? `${udrensPreview?.stier.length ?? 0} fil(er) slettes permanent — bytes kan IKKE fortrydes. Klik igen for at bekræfte.`
                      : !udrensPreview ? 'Kontrollerer…' : udrensPreview.kanUdrenses ? 'Slet permanent…' : 'Slet permanent (blokeret)'}
                  </BtnLabel>
                </Pressable> : null}
              </>
            ) : <>
              {media.uploadStatus === 'klar' && onErstatFil ? (
                <Pressable disabled={medieAktionBusy} style={[styles.neutral, medieAktionBusy && { opacity: .45 }]}
                  onPress={() => { void runMedieAktion(onErstatFil); }}>
                  <BtnLabel color={Colors.textMuted}>{medieAktionBusy ? 'Erstatter…' : 'Erstat fil…'}</BtnLabel>
                </Pressable>
              ) : null}
              <Pressable disabled={!media.relationId} style={styles.neutral} onPress={onFjern}><BtnLabel color={Colors.textMuted}>Fjern tilknytning</BtnLabel></Pressable>
              <Pressable disabled={!anvendelse} style={[styles.slet, !anvendelse && { opacity: .45 }]} onPress={() => {
                if (!anvendelse) return;
                if (erIBrug && !bekraeftSlet) { setBekraeftSlet(true); return; }
                onSlet();
              }}><BtnLabel size={bekraeftSlet ? 9 : undefined} color="#fff">{bekraeftSlet ? sletAdvarsel : anvendelse ? 'Slet billede' : 'Kontrollerer…'}</BtnLabel></Pressable>
            </>}
          </View>
          {media.uploadStatus === 'fjernet' && udrensPreview && !udrensPreview.kanUdrenses ? (
            <View style={{ marginTop: 8 }}>
              {udrensPreview.blokeringer.map((blokering) => (
                <Body key={blokering} size={11.5} color={Colors.danger}>· {blokering}</Body>
              ))}
            </View>
          ) : null}
        </ScrollView>
      </View>
      {lightbox && erBillede && uri && media.uploadStatus === 'klar' ? (
        <Lightbox items={[{ id: media.id, uri, titel: media.titel }]} index={0} onClose={() => setLightbox(false)} onNavigate={() => {}} />
      ) : null}
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(34,31,26,.45)' },
  sheet: { maxHeight: '92%', backgroundColor: Colors.paperBg, borderTopLeftRadius: Radius.sheet, borderTopRightRadius: Radius.sheet, borderTopWidth: 1, borderColor: Border.light },
  preview: { width: '100%', height: 260, borderRadius: 10, backgroundColor: Colors.beige2 },
  dokument: { alignItems: 'center', justifyContent: 'center', gap: 7 },
  heading: { marginTop: 20, marginBottom: 7 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.chip, paddingHorizontal: 10, paddingVertical: 5 },
  chipAktiv: { backgroundColor: Colors.bordeaux, borderColor: Colors.bordeaux },
  input: { backgroundColor: '#fff', borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.field, paddingHorizontal: 10, paddingVertical: 8, marginTop: 8, fontFamily: 'HankenGrotesk_400Regular', fontSize: 13, color: Colors.ink },
  gem: { backgroundColor: Colors.konklusionGroen, borderRadius: Radius.field, paddingHorizontal: 14, paddingVertical: 9, alignSelf: 'flex-start', marginTop: 10 },
  neutral: { borderWidth: 1, borderColor: Border.medium, borderRadius: Radius.field, paddingHorizontal: 12, paddingVertical: 9 },
  slet: { backgroundColor: Colors.danger, borderRadius: Radius.field, paddingHorizontal: 12, paddingVertical: 9 },
  anvendelseHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: 20, marginBottom: 7 },
  anvendelseRad: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: Colors.beige2, borderRadius: Radius.field, paddingHorizontal: 10, paddingVertical: 8 },
});

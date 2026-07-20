// Redaktør-medieupload (mediehåndtering Slice 0g + billedstørrelser Slice B2). Adskilt fra media.ts
// (ren læsevej): denne fil rører device-native API'er (billedvælger, filsystem, genkodning) og er
// derfor ikke unit-testet — kald gennem redaktionWrite.ts's testede buildRpcCall/submitChange.
import * as ImagePicker from 'expo-image-picker';
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import { File } from 'expo-file-system';
import * as Crypto from 'expo-crypto';
import { supabase } from './supabase';
import { buildShaStoragePaths, hexEncode } from './mediaPaths';
import type { MediaTier } from './mediaPaths';

export type PickedImage = {
  uri: string;
  mimeType: string;
  byteSize: number | null;
  width: number | null;
  height: number | null;
  fileName: string | null;
};

// Bruger biblioteksvælgeren (ikke kamera) — matcher den primære brugssituation: digitalisering
// af eksisterende portrætter/dokumenter, ikke live-optagelse. Beder om tilladelse først (SDK 56
// kræver eksplicit request; launchImageLibraryAsync fejler stille uden).
export async function pickImage(): Promise<PickedImage | null> {
  const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!perm.granted) return null;
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: false,
    quality: 1,
  });
  if (result.canceled || !result.assets.length) return null;
  const a = result.assets[0];
  return {
    uri: a.uri,
    mimeType: a.mimeType ?? 'image/jpeg',
    byteSize: a.fileSize ?? null,
    width: a.width ?? null,
    height: a.height ?? null,
    fileName: a.fileName ?? null,
  };
}

// Læs den valgte fils rå bytes til upload (SDK 56 File-klassen — readAsStringAsync er
// deprecated/flyttet til expo-file-system/legacy, se mobile/AGENTS.md-mandatet).
export async function readFileBytes(localUri: string): Promise<Uint8Array> {
  const file = new File(localUri);
  return file.bytes();
}

export type { MediaTier } from './mediaPaths';
export type ResizedVariant = { tier: MediaTier; uri: string; storagePath: string; mimeType: string; byteSize: number; bredde: number; hoejde: number };
export type BuiltVariants = Record<MediaTier, ResizedVariant> & { sha256: string };
type ResizedVariantWithoutPath = Omit<ResizedVariant, 'storagePath'>;

// Størrelsestrin (billedstørrelser/lightbox 2026-07-05, plan §1). 'large' erstatter den rå original
// som det øverste niveau — ingen separat ukomprimeret original gemmes (§6.4).
const TIER_SPECS: Record<MediaTier, { width: number; quality: number }> = {
  thumb:  { width: 500,  quality: 0.7 },
  medium: { width: 1100, quality: 0.78 },
  large:  { width: 2000, quality: 0.82 },
};

// Én uafhængig kontekst pr. tier (ikke kædet fra forrige tier) — hver tier genkodes fra den
// oprindelige fil, så kvalitetstab ikke akkumuleres tier-til-tier. Skalerer aldrig OP over
// originalens bredde (blur + spildte bytes for et lille kildebillede).
async function resizeToTier(originalUri: string, originalWidth: number | null, tier: MediaTier): Promise<ResizedVariantWithoutPath> {
  const spec = TIER_SPECS[tier];
  const targetWidth = originalWidth ? Math.min(spec.width, originalWidth) : spec.width;
  const context = ImageManipulator.manipulate(originalUri);
  context.resize({ width: targetWidth, height: null });
  const rendered = await context.renderAsync();
  const saved = await rendered.saveAsync({ format: SaveFormat.JPEG, compress: spec.quality });
  return {
    tier, uri: saved.uri, mimeType: 'image/jpeg',
    byteSize: new File(saved.uri).size, bredde: saved.width, hoejde: saved.height,
  };
}

// Genkoder det valgte billede til alle tre tiers. Native billedbehandling (ikke canvas) —
// afkoder HEIC/enhver enhedsformat problemfrit, så 'large' også reelt fikser HEIC-uploads.
export async function buildVariants(picked: PickedImage): Promise<BuiltVariants> {
  const [thumb, medium, large] = await Promise.all([
    resizeToTier(picked.uri, picked.width, 'thumb'),
    resizeToTier(picked.uri, picked.width, 'medium'),
    resizeToTier(picked.uri, picked.width, 'large'),
  ]);
  const largeBytes = new Uint8Array(await readFileBytes(large.uri));
  const digest = await Crypto.digest(Crypto.CryptoDigestAlgorithm.SHA256, largeBytes);
  const sha256 = hexEncode(new Uint8Array(digest));
  const paths = buildShaStoragePaths(sha256);
  return {
    sha256,
    thumb: { ...thumb, storagePath: paths.thumb },
    medium: { ...medium, storagePath: paths.medium },
    large: { ...large, storagePath: paths.large },
  };
}

function isDuplicateUploadError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const candidate = error as { statusCode?: unknown; error?: unknown; message?: unknown };
  return candidate.statusCode === 'Duplicate'
    || candidate.error === 'Duplicate'
    || (typeof candidate.message === 'string'
      && candidate.message.toLowerCase().includes('the resource already exists'));
}

// Læs+upload som ÉN enhed: den delte sti-værdi bruges direkte (ikke genudledt af kalderen fra et
// allerede-bygget RPC-args-objekt) — undgår at "bytes lander hvor DB-rækken siger" kun holder,
// fordi to steder tilfældigvis kopierer samme streng. Kaldes fra redaktionWrite.ts's submitChange.
export async function performUpload(localUri: string, storagePath: string, mimeType: string): Promise<void> {
  if (!supabase) throw new Error('Supabase ikke konfigureret');
  const bytes = await readFileBytes(localUri);
  const { error } = await supabase.storage.from('media').upload(storagePath, bytes, {
    contentType: mimeType,
    upsert: false,
  });
  if (error && !isDuplicateUploadError(error)) throw new Error(error.message);
}

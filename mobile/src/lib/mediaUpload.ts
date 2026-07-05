// Redaktør-medieupload (mediehåndtering Slice 0g). Adskilt fra media.ts (ren læsevej): denne fil
// rører device-native API'er (billedvælger, filsystem) og er derfor ikke unit-testet — kald
// gennem redaktionWrite.ts's testede buildRpcCall/submitChange.
import * as ImagePicker from 'expo-image-picker';
import { File } from 'expo-file-system';
import { supabase } from './supabase';

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

// Deterministisk-nok, kollisionsfri sti under redaktørens eget upload-rum. Filendelse fra
// mimeType (ikke det oprindelige filnavn — undgår mellemrum/specialtegn i storage_path).
const EXT_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic',
};
export function buildStoragePath(mimeType: string): string {
  const ext = EXT_BY_MIME[mimeType] ?? 'jpg';
  const rand = Math.random().toString(36).slice(2, 10);
  return `redaktor/${Date.now()}-${rand}.${ext}`;
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
  if (error) throw new Error(error.message);
}

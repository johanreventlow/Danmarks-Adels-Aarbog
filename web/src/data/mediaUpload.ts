// Redaktør-medieupload til web (mediehåndtering Slice 0g). Porteret fra
// mobile/src/lib/mediaUpload.ts, tilpasset browseren: et <input type="file">'s File-objekt er
// allerede brugbart direkte af supabase-js's storage.upload — intet separat "læs bytes"-trin
// nødvendigt (mobile skal via expo-file-system, web ikke).
import { supabase } from '../supabase';

const EXT_BY_MIME: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic',
};
export function buildStoragePath(mimeType: string): string {
  const ext = EXT_BY_MIME[mimeType] ?? 'jpg';
  const rand = Math.random().toString(36).slice(2, 10);
  return `redaktor/${Date.now()}-${rand}.${ext}`;
}

// Upload den valgte fil til den private 'media'-bucket på den angivne sti.
export async function performUpload(file: File, storagePath: string): Promise<void> {
  const { error } = await supabase.storage.from('media').upload(storagePath, file, {
    contentType: file.type || 'application/octet-stream',
    upsert: false,
  });
  if (error) throw new Error(error.message);
}

// Redaktør-medieupload til web (mediehåndtering Slice 0g + billedstørrelser Slice B2). Porteret fra
// mobile/src/lib/mediaUpload.ts, tilpasset browseren: Canvas/createImageBitmap i stedet for
// expo-image-manipulator (samme tre størrelsestrin, samme mønster — ikke delt kode, jf.
// buildBidirectionalColumns-præcedensen: ét interaktionsmønster, to uafhængige implementeringer).
import { supabase } from '../supabase';

export type MediaTier = 'thumb' | 'medium' | 'large';
export type ResizedVariant = { tier: MediaTier; file: Blob; storagePath: string; mimeType: string; byteSize: number; bredde: number; hoejde: number };

// Størrelsestrin (billedstørrelser/lightbox 2026-07-05, plan §1). 'large' erstatter den rå original
// som det øverste niveau — ingen separat ukomprimeret original gemmes (§6.4).
const TIER_SPECS: Record<MediaTier, { width: number; quality: number }> = {
  thumb:  { width: 500,  quality: 0.7 },
  medium: { width: 1100, quality: 0.78 },
  large:  { width: 2000, quality: 0.82 },
};

function buildStoragePathBase(): string {
  const rand = Math.random().toString(36).slice(2, 10);
  return `redaktor/${Date.now()}-${rand}`;
}

// En browser-canvas kan ikke afkode HEIC (modsat expo-image-manipulator på mobile, som bruger
// enhedens native billedafkoder) — fejl EKSPLICIT frem for at producere tre tomme/korrupte
// varianter. createImageBitmap er den bredest understøttede afkoder til canvas-formål.
async function decodeImage(file: File): Promise<ImageBitmap> {
  try {
    return await createImageBitmap(file);
  } catch {
    throw new Error(
      `Kunne ikke afkode billedet (${file.type || 'ukendt format'}). HEIC understøttes ikke i ` +
      'browseren — konvertér til JPEG/PNG, eller upload fra mobilappen.'
    );
  }
}

// Tegner samme afkodede bitmap på tre uafhængige canvas'er (ikke kædet tier-til-tier) — undgår
// akkumuleret kvalitetstab og genbruger den dyre afkodning ét sted. Skalerer aldrig OP over
// bitmapens bredde (blur + spildte bytes for et lille kildebillede).
async function resizeToTier(bitmap: ImageBitmap, tier: MediaTier, storagePath: string): Promise<ResizedVariant> {
  const spec = TIER_SPECS[tier];
  const scale = Math.min(1, spec.width / bitmap.width);
  const bredde = Math.round(bitmap.width * scale);
  const hoejde = Math.round(bitmap.height * scale);
  const canvas = document.createElement('canvas');
  canvas.width = bredde;
  canvas.height = hoejde;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Canvas (2d) understøttes ikke i denne browser');
  ctx.drawImage(bitmap, 0, 0, bredde, hoejde);
  const blob = await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Kunne ikke kode billedet til JPEG'))), 'image/jpeg', spec.quality);
  });
  return { tier, file: blob, storagePath, mimeType: 'image/jpeg', byteSize: blob.size, bredde, hoejde };
}

// Genkoder den valgte fil til alle tre tiers.
export async function buildVariants(file: File): Promise<Record<MediaTier, ResizedVariant>> {
  const bitmap = await decodeImage(file);
  try {
    const base = buildStoragePathBase();
    const [thumb, medium, large] = await Promise.all([
      resizeToTier(bitmap, 'thumb', `${base}-thumb.jpg`),
      resizeToTier(bitmap, 'medium', `${base}-medium.jpg`),
      resizeToTier(bitmap, 'large', `${base}-large.jpg`),
    ]);
    return { thumb, medium, large };
  } finally {
    bitmap.close();
  }
}

// Upload den valgte fil til den private 'media'-bucket på den angivne sti.
export async function performUpload(file: Blob, storagePath: string): Promise<void> {
  const { error } = await supabase.storage.from('media').upload(storagePath, file, {
    contentType: file.type || 'application/octet-stream',
    upsert: false,
  });
  if (error) throw new Error(error.message);
}

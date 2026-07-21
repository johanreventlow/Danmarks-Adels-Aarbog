export type MediaTier = 'thumb' | 'medium' | 'large';

export function hexEncode(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function buildShaStoragePaths(sha: string): Record<MediaTier, string> {
  const base = `redaktor/${sha.slice(0, 2)}/${sha}`;
  return {
    thumb: `${base}-thumb.jpg`,
    medium: `${base}-medium.jpg`,
    large: `${base}-large.jpg`,
  };
}

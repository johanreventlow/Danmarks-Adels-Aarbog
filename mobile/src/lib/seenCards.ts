// Set-hukommelse for feed'et (fase1-design.md §5.3, §5.5). Klienten husker lokalt de
// seneste sete kort-nøgler med tidsstempel; scoringen straffer gensyn med aftagende vægt.
// Ingen serverside-tracking, intet GDPR-aftryk — ren AsyncStorage, spejler bookmarks.ts'
// tolerante læs/skriv-mønster (fejl sluges, korrupt indhold degraderer til tomt).
import AsyncStorage from '@react-native-async-storage/async-storage';

export const SEEN_KEY = 'daa_feed_seen';
export const SEEN_CAP = 300;
const DEBOUNCE_MS = 800;

// kort-id → epoch-dag (dage siden epoch) da kortet sidst blev registreret som set.
export type SeenMap = Record<string, number>;

async function safeRead(): Promise<SeenMap> {
  try {
    const raw = await AsyncStorage.getItem(SEEN_KEY);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    return parsed != null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as SeenMap)
      : {};
  } catch {
    return {};
  }
}
async function safeWrite(map: SeenMap): Promise<void> {
  try {
    await AsyncStorage.setItem(SEEN_KEY, JSON.stringify(map));
  } catch {
    /* ikke-kritisk — feed'ets friskheds-hukommelse, ikke brugerdata */
  }
}

// LRU-beskæring: behold de SEEN_CAP nyeste poster (højeste epochDag); ældste ryger først.
function capOldest(map: SeenMap, cap: number): SeenMap {
  const entries = Object.entries(map);
  if (entries.length <= cap) return map;
  entries.sort((a, b) => b[1] - a[1]);
  return Object.fromEntries(entries.slice(0, cap));
}

export interface SeenStore {
  load(): Promise<SeenMap>;
  markSeen(ids: string[], epochDay: number): void;
}

export function createSeenStore(): SeenStore {
  let pending: SeenMap = {};
  let timer: ReturnType<typeof setTimeout> | null = null;
  // Serialiserer alle læs-flet-skriv-runder, så to hurtigt-på-hinanden-følgende flushes
  // aldrig overlapper (én runde læser ALTID storage EFTER at den forrige er skrevet).
  let writeQueue: Promise<void> = Promise.resolve();

  const flush = () => {
    timer = null;
    const toWrite = pending;
    pending = {};
    writeQueue = writeQueue.then(async () => {
      const current = await safeRead();
      const merged = capOldest({ ...current, ...toWrite }, SEEN_CAP);
      await safeWrite(merged);
    });
  };

  return {
    load: () => safeRead(),
    markSeen: (ids, epochDay) => {
      if (ids.length === 0) return;
      for (const id of ids) pending[id] = epochDay;
      if (timer) clearTimeout(timer);
      timer = setTimeout(flush, DEBOUNCE_MS);
    },
  };
}

// Ren afledning (spec §5.3): <3 dage → 0.25; <7 → 0.5; <14 → 0.75; ældre udelades (scoringen
// bruger standardvægt 1.0 for kort uden en post — se score.ts).
export function toSeenWeights(seen: SeenMap, todayEpochDay: number): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [id, seenDay] of Object.entries(seen)) {
    const age = todayEpochDay - seenDay;
    if (age < 3) out[id] = 0.25;
    else if (age < 7) out[id] = 0.5;
    else if (age < 14) out[id] = 0.75;
  }
  return out;
}

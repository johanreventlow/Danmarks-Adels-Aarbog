// Set-hukommelse for feed'et — web-udgaven af mobile/src/lib/seenCards.ts. localStorage er
// synkront, så der er intet at debounce mod et async lager: markSeen skriver direkte
// (batched i JS via ét sammenlagt objekt pr. kald), men holder samme decay-model og
// LRU-cap som mobil, så feed-motorens vægtning opfører sig identisk på tværs af platforme.
export const SEEN_KEY = 'daa_feed_seen';
export const SEEN_CAP = 300;

// kort-id → epoch-dag (dage siden epoch) da kortet sidst blev registreret som set.
export type SeenMap = Record<string, number>;

function safeRead(): SeenMap {
  try {
    const raw = localStorage.getItem(SEEN_KEY);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    return parsed != null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? (parsed as SeenMap)
      : {};
  } catch {
    return {};
  }
}
function safeWrite(map: SeenMap): void {
  try {
    localStorage.setItem(SEEN_KEY, JSON.stringify(map));
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
  return {
    // async-signatur bevaret (matcher mobilens kontrakt 1:1), selvom læsningen er synkron her.
    load: () => Promise.resolve(safeRead()),
    markSeen: (ids, epochDay) => {
      if (ids.length === 0) return;
      const current = safeRead();
      for (const id of ids) current[id] = epochDay;
      safeWrite(capOldest(current, SEEN_CAP));
    },
  };
}

// Ren afledning — identisk med mobilens seenCards.ts (spec §5.3): <3 dage → 0.25; <7 → 0.5;
// <14 → 0.75; ældre udelades (scoringen bruger standardvægt 1.0 for kort uden en post).
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

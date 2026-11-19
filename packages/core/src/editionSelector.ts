// Udgavevælger til personsiden: én chip pr. udgave (projektejeren 2026-11-19; afløser 6e §5.5 afgørelse 11's chip pr.
// post). Har udgaven flere poster for personen (fx Conrad 392: V-1 og henvisningen III-58 i 2018-20), bærer chippen
// posten med den fulde biografi: en bogpost før overgangsdata, derefter den længste tekst. Etiketten er kun udgavens
// navn; alle poster står stadig under »Kilde i Aarbogen«. En udgave med fakta men ingen biografi får en udgave-chip.
// Standard = nyeste udgave med en post.
import type { BioSourceVersion, BioSourceVersionV2 } from './bioVersions';
import type { Udgave } from './editionFacts';

export type UdgaveChip =
  // poster: recordRef for ALLE personens poster i udgaven (også dem, chippen ikke viser, fx III-58), så et klik på en
  // kildelinje til en af dem kan vælge udgavens chip.
  | { art: 'post'; sourceId: string; label: string; version: BioSourceVersion; poster: string[] }
  | { art: 'udgave'; sourceId: string; label: string };

export type UdgaveVaelger = {
  chips: UdgaveChip[];
  standard: number;
  form: 'ingen' | 'chips' | 'skift';
};

function versionSourceId(v: BioSourceVersion, udgaver: Udgave[]): string {
  const id = (v as Partial<BioSourceVersionV2>).sourceId;
  if (typeof id === 'number') return String(id);
  return udgaver.find((u) => u.label === v.sourceLabel)?.sourceId ?? `label:${v.sourceLabel}`;
}

// Fuld biografi først: bogpost før overgangsdata, så længste tekst; ved lighed den første i input.
const bedre = (a: BioSourceVersion, b: BioSourceVersion): boolean => {
  const ab = a.provenanceKind === 'source_record', bb = b.provenanceKind === 'source_record';
  if (ab !== bb) return ab;
  return a.narrativeText.trim().length > b.narrativeText.trim().length;
};

export function byggUdgaveVaelger(
  versioner: BioSourceVersion[],
  udgaver: Udgave[],
  udgaverMedFakta: string[],
): UdgaveVaelger {
  const aarFor = new Map<string, number | null>();
  for (const u of udgaver) aarFor.set(u.sourceId, u.aar);

  type Intern = { chip: UdgaveChip; aar: number | null; num: number };
  const num = (id: string) => {
    const n = Number(id);
    return Number.isFinite(n) ? n : Number.MAX_SAFE_INTEGER;
  };
  const intern: Intern[] = [];
  const medPost = new Set<string>();

  // Én post pr. udgave: den med den fulde biografi.
  const valgt = new Map<string, BioSourceVersion>();
  const poster = new Map<string, string[]>();
  for (const v of versioner) {
    if (v.narrativeText.trim() === '') continue;
    const sourceId = versionSourceId(v, udgaver);
    if (v.recordRef) (poster.get(sourceId) ?? poster.set(sourceId, []).get(sourceId)!).push(v.recordRef);
    const nu = valgt.get(sourceId);
    if (!nu || bedre(v, nu)) valgt.set(sourceId, v);
  }
  for (const [sourceId, v] of valgt) {
    medPost.add(sourceId);
    const aar = aarFor.get(sourceId) ?? (v as Partial<BioSourceVersionV2>).sourceYear ?? null;
    const label = udgaver.find((u) => u.sourceId === sourceId)?.label ?? v.sourceLabel;
    intern.push({ chip: { art: 'post', sourceId, label, version: v, poster: poster.get(sourceId) ?? [] }, aar, num: num(sourceId) });
  }
  for (const sourceId of new Set(udgaverMedFakta)) {
    if (medPost.has(sourceId)) continue;
    const u = udgaver.find((x) => x.sourceId === sourceId);
    intern.push({
      chip: { art: 'udgave', sourceId, label: u?.label ?? sourceId },
      aar: u?.aar ?? null,
      num: num(sourceId),
    });
  }

  intern.sort((a, b) => {
    if (a.aar !== b.aar) {
      if (a.aar === null) return 1;
      if (b.aar === null) return -1;
      return b.aar - a.aar;
    }
    return a.num - b.num;
  });

  const chips = intern.map((i) => i.chip);
  const form = chips.length <= 1 ? 'ingen' : chips.some((c) => c.art === 'post') ? 'chips' : 'skift';
  // Standard: første chip i nyeste udgave med en post; ellers første chip (udgave-chip).
  const foersteMedPost = chips.findIndex((c) => c.art === 'post');
  const standard = foersteMedPost >= 0 ? foersteMedPost : 0;
  return { chips, standard, form };
}

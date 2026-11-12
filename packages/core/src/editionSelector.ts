// Udgavevælger til personsiden: én chip pr. biografipost, plus en chip for en udgave der har
// fakta men ingen biografi. Standard = nyeste udgaves længste tekst (spec 6e §5.5, afgørelse 11).
import type { BioSourceVersion, BioSourceVersionV2 } from './bioVersions';
import type { Udgave } from './editionFacts';
import { visbarPostEtiket } from './recordLabel';

export type UdgaveChip =
  | { art: 'post'; sourceId: string; label: string; version: BioSourceVersion }
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

function postLabel(v: BioSourceVersion): string {
  if (v.provenanceKind !== 'source_record') return `${v.sourceLabel} · overgangsdata`;
  const etiket = visbarPostEtiket(v.recordLabel);
  return etiket ? `${v.sourceLabel} · ${etiket}` : v.sourceLabel;
}

export function byggUdgaveVaelger(
  versioner: BioSourceVersion[],
  udgaver: Udgave[],
  udgaverMedFakta: string[],
): UdgaveVaelger {
  const aarFor = new Map<string, number | null>();
  for (const u of udgaver) aarFor.set(u.sourceId, u.aar);

  type Intern = { chip: UdgaveChip; aar: number | null; num: number; laengde: number };
  const num = (id: string) => {
    const n = Number(id);
    return Number.isFinite(n) ? n : Number.MAX_SAFE_INTEGER;
  };
  const intern: Intern[] = [];
  const medPost = new Set<string>();

  for (const v of versioner) {
    const sourceId = versionSourceId(v, udgaver);
    medPost.add(sourceId);
    const aar = aarFor.get(sourceId) ?? (v as Partial<BioSourceVersionV2>).sourceYear ?? null;
    intern.push({
      chip: { art: 'post', sourceId, label: postLabel(v), version: v },
      aar,
      num: num(sourceId),
      laengde: v.narrativeText.length,
    });
  }
  for (const sourceId of new Set(udgaverMedFakta)) {
    if (medPost.has(sourceId)) continue;
    const u = udgaver.find((x) => x.sourceId === sourceId);
    intern.push({
      chip: { art: 'udgave', sourceId, label: u?.label ?? sourceId },
      aar: u?.aar ?? null,
      num: num(sourceId),
      laengde: 0,
    });
  }

  intern.sort((a, b) => {
    if (a.aar !== b.aar) {
      if (a.aar === null) return 1;
      if (b.aar === null) return -1;
      return b.aar - a.aar;
    }
    if (a.num !== b.num) return a.num - b.num;
    return b.laengde - a.laengde;
  });

  const chips = intern.map((i) => i.chip);
  const form = chips.length <= 1 ? 'ingen' : chips.some((c) => c.art === 'post') ? 'chips' : 'skift';
  return { chips, standard: 0, form };
}

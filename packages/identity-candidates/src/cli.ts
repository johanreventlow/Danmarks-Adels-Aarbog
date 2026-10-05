import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { personaFrames, personFrames, udenAarstal, type MatchPayload, type PersonaExportRow } from './frames';
import { rankCandidates, rankConfig } from './rank';
import { calibrate } from './calibrate';

const GENERATOR_VERSION = 'identity-candidates-1.0';

function arg(name: string, required = true): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  const v = i >= 0 ? process.argv[i + 1] : undefined;
  if (required && !v) { console.error(`mangler --${name}`); process.exit(2); }
  return v;
}

const cmd = process.argv[2];
if (cmd !== 'generate' && cmd !== 'calibrate') { console.error('brug: cli.ts generate|calibrate …'); process.exit(2); }

if (cmd === 'generate') {
  // export-input.sql: serverens input og dens hash; CLI'en hasher intet selv.
  const exp = JSON.parse(readFileSync(arg('input')!, 'utf8')) as {
    input_spec: unknown; input_sha256: string; input: { personas: PersonaExportRow[]; persons: MatchPayload };
  };
  const personaRows = exp.input.personas;
  const payload = exp.input.persons;
  const sourceId = Number(arg('source-id'));
  const topK = Number(arg('top-k', false) ?? 3);
  if (!Number.isInteger(topK) || topK < 1) { console.error('--top-k skal være et positivt heltal'); process.exit(2); }
  const evidensNormaliseret = process.argv.includes('--evidens-normaliseret');
  const { frames, origins } = personaFrames(personaRows);
  const persons = personFrames(payload);
  const candidates = rankCandidates(frames, persons, { topK, origins, evidensNormaliseret });
  const run = {
    source_id: sourceId, generator_version: GENERATOR_VERSION, input_spec: exp.input_spec,
    input_sha256: exp.input_sha256, config: { ...rankConfig({ evidensNormaliseret }), topK },
  };
  const uden = frames.filter((f) => !f.nameKey).length;
  const out = arg('out')!;
  // Personas uden parsebart fødsels- og dødsår (kun id'er) — kalibreringen rapporterer dem for sig (spec §8.1).
  const udenAar = udenAarstal(frames);
  writeFileSync(out, JSON.stringify({ run, candidates, stats: { personas: frames.length, uden_navn: uden, uden_aar: udenAar } }), 'utf8');
  chmodSync(out, 0o600);
  const tiers = candidates.filter((c) => c.rank === 1).reduce<Record<string, number>>((m, c) => ({ ...m, [c.tier]: (m[c.tier] ?? 0) + 1 }), {});
  console.log(`CANDIDATES_OK personas=${frames.length} uden_navn=${uden} kandidater=${candidates.length} rang1_tier=${JSON.stringify(tiers)}`);
}

if (cmd === 'calibrate') {
  const data = JSON.parse(readFileSync(arg('candidates')!, 'utf8'));
  const truth = JSON.parse(readFileSync(arg('truth')!, 'utf8'));
  console.log('CALIBRATION ' + JSON.stringify(calibrate(data.candidates, truth, data.stats.personas, data.stats.uden_navn,
    new Set<string>(data.stats.uden_aar ?? []))));
}

// Trin 6b (plan Task 10/15): kalibrerings-CLI. Læser og skriver kun filer under en privat mappe (0600) og udskriver kun
// antal. Bruges af scripts/calibrate-publication-control.sh.
//   split           --input <export-input.json> --pairs <par.json> --out-dir <mappe>
//   cluster-calibrate --candidates <kandidatfil> --truth <facit.json>
//   years           --input <export-input.json> --persons <person-id'er.json>
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { partitionPairs, mutateSameAs, clusterCalibrate, yearCoverage, type Pair } from './calibration';
import { personFrames } from './frames';

function arg(name: string): string {
  const i = process.argv.indexOf(`--${name}`);
  const v = i >= 0 ? process.argv[i + 1] : undefined;
  if (!v) { console.error(`mangler --${name}`); process.exit(2); }
  return v;
}
const write = (f: string, x: unknown) => { writeFileSync(f, JSON.stringify(x), 'utf8'); chmodSync(f, 0o600); };

const cmd = process.argv[2];
if (cmd === 'split') {
  // Én inputkopi pr. del: same_as udvidet med delens par. input_sha256 sættes af scriptet bagefter (serverens kanoniske
  // hash af kopiens input); indtil da er den tom, så en glemt hash fejler i generatoren/indsættelsen.
  const exp = JSON.parse(readFileSync(arg('input'), 'utf8'));
  const pairs = JSON.parse(readFileSync(arg('pairs'), 'utf8')) as Pair[];
  const dir = arg('out-dir');
  const parts = partitionPairs(exp.input.same_as as Pair[], pairs);
  parts.forEach((part, i) => {
    const nn = String(i + 1).padStart(2, '0');
    const input = { ...exp.input, same_as: mutateSameAs(exp.input.same_as as Pair[], part) };
    write(join(dir, `input-b${nn}.inner.json`), input);
    write(join(dir, `input-b${nn}.json`), { ...exp, input, input_sha256: '' });
  });
  const sizes = parts.map((p) => p.length);
  console.log(`SPLIT_OK par=${pairs.length} kopier=${parts.length} stoerste=${Math.max(0, ...sizes)} mindste=${Math.min(...sizes)}`);
} else if (cmd === 'cluster-calibrate') {
  const data = JSON.parse(readFileSync(arg('candidates'), 'utf8'));
  const truth = JSON.parse(readFileSync(arg('truth'), 'utf8'));
  console.log('CLUSTER_CALIBRATION ' + JSON.stringify(clusterCalibrate(data.candidates, truth)));
} else if (cmd === 'years') {
  const exp = JSON.parse(readFileSync(arg('input'), 'utf8'));
  const ids = new Set((JSON.parse(readFileSync(arg('persons'), 'utf8')) as number[]).map(Number));
  console.log('YEARS ' + JSON.stringify({ year_fallback: exp.input_spec?.year_fallback ?? null,
    ...yearCoverage(personFrames(exp.input.persons), ids) }));
} else {
  console.error('brug: calibration-cli.ts split|cluster-calibrate|years …'); process.exit(2);
}

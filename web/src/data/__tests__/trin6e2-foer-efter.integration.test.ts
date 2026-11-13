// Trin 6e-2, Task 8: klientens byggere kørt på ægte anon-eksport fra en kopi af prod FØR og EFTER DB-migrationen og
// dataceremonien. Springes over, medmindre DAA_6E2_DATA_DIR peger på en mappe med undermapperne foer/ og efter/ (JSON
// pr. læst relation/RPC, se eksportscriptet i opgaverapporten). Eksporten ligger aldrig i repoet. Testen udskriver
// ingen prosa; kun etiketter, sidetal og id'er skrives til vist-strenge.json i datamappen.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  b6Noter, bogensNummer, buildPersonFacts, byggUdgaveFakta, byggUdgaveVaelger, citationRowsTilProveniens,
  buildProvenanceSources, collapseSameAs, coordinateRowToExtId, kildeLinje, linjerForUdgave,
  mapFamilieKilder, mapPublicBioSourceVersionsV2, optraederSom, sorterKilder, udgaverMedFakta,
  type AppPerson, type LinjeRaekke, type PublicCoordinateRow, type PublicPersonFactRow, type RaaCitationRow, type UdgaveFaktaInput,
} from '@daa/core';
import { factSource } from '../../../../packages/core/src/personFacts';
import { buildLineage, erTekniskLinje, kanoniskeLinjerPrPerson, stamtavleSkemaOpslag, synligeLinjer, type LineageSchemeRows } from '../lineage';
import { byggLinjeRaekker } from '../linjeRaekker';
import { buildSources } from '../sources';
import { byggUdgaveModel, SLUKKET_ENIGHED } from '../udgaver';
import type { RawLineageContext, RawSource } from '../types';

const DIR = process.env.DAA_6E2_DATA_DIR;
type Fase = 'foer' | 'efter';

// Det tjekkede udsnit (valgt ud fra eksporten): komponenten med 392 som kanonisk (255/392/1198) og komponenten med 149
// som kanonisk (1093/149). Medlemmerne udledes af samme_som-foldningen, ikke hårdkodet.
const FOKUS_CONRAD = '392';
const FOKUS_PLACERET = '149';
const FORBUDT = /record-|legacy-source:|Linje 1939/;

function laes<T = Record<string, unknown>>(fase: Fase, navn: string): T[] {
  return JSON.parse(readFileSync(join(DIR!, fase, `${navn}.json`), 'utf8')) as T[];
}

type Bygget = ReturnType<typeof byg>;

function byg(fase: Fase) {
  const coords = laes<PublicCoordinateRow>(fase, 'coordinates');
  const extIds = coords.map(coordinateRowToExtId);
  const sources = laes<RawSource>(fase, 'source');
  const lineageRows = laes<RawLineageContext>(fase, 'lineage');
  const schemeRows: LineageSchemeRows = {
    schemes: laes(fase, 'lineage_scheme'), entries: laes(fase, 'lineage_scheme_entry'),
    mappings: laes(fase, 'lineage_scheme_entry_lineage'),
  };
  // samme_som-model som i loadModel: kun afklarede relationer; subjekt = alias, objekt = kanonisk.
  const afklaret = new Set(laes<{ target_id: number }>(fase, 'samme_som_conclusion').map((c) => String(c.target_id)));
  const edges = laes<{ id: number; subjekt_id: number; objekt_id: number }>(fase, 'samme_som')
    .filter((r) => afklaret.has(String(r.id))).map((r) => ({ alias: String(r.subjekt_id), canonical: String(r.objekt_id) }));
  const persons: AppPerson[] = laes<{ id: number; koen: string | null; privat: boolean | null }>(fase, 'persons').map((p) => ({
    id: String(p.id), name: '', born: null, died: null, years: '', title: '', bio: '', privat: Boolean(p.privat),
    koen: p.koen === 'mand' || p.koen === 'kvinde' ? p.koen : undefined,
  }));
  const extMap = new Map(extIds.map((x) => [String(x.person_id), { linje: x.linje, nr: x.nr, nr_label: x.nr_label ?? null }]));
  const collapsed = collapseSameAs({ persons, unions: [], parentChild: [] }, edges, extMap);
  const canon = collapsed.canonicalIdById;
  const skema = stamtavleSkemaOpslag(schemeRows);
  const sourcesBy = buildSources(extIds, sources, canon, skema);
  const lineage = buildLineage(extIds, lineageRows, canon, schemeRows, sources);
  const linjeRaekkerBy = byggLinjeRaekker(extIds, sources, canon, schemeRows);
  const { udgaver, udgaveForPersonRaekke } = byggUdgaveModel(sources, extIds);
  return { coords, extIds, canon, mergedFrom: collapsed.mergedFrom, sourcesBy, lineage, linjeRaekkerBy, udgaver, udgaveForPersonRaekke };
}

// Personens visning som usePersonVisning bygger den, for hver valgbar udgave (null = ingen valgt).
function visning(fase: Fase, b: Bygget, focusId: string) {
  const medlemmer = new Set((b.mergedFrom[focusId] ?? [{ personId: focusId }]).map((m) => String(m.personId)));
  const iGruppe = <T extends { person_id: number | string }>(rows: T[]) => rows.filter((r) => medlemmer.has(String(r.person_id)));
  const bioRows = iGruppe(laes<{ person_id: number }>(fase, 'bio_v2'));
  const factRows = iGruppe(laes<PublicPersonFactRow>(fase, 'facts'));
  const bioVersions = mapPublicBioSourceVersionsV2(bioRows);
  const faktaInput: UdgaveFaktaInput = {
    rows: factRows, udgaver: b.udgaver, udgaveForPersonRaekke: b.udgaveForPersonRaekke, fritekstKilde: {},
    slukketEnighed: SLUKKET_ENIGHED,
  };
  const vaelger = byggUdgaveVaelger(bioVersions, b.udgaver, udgaverMedFakta(faktaInput));
  const raekker = b.linjeRaekkerBy[focusId] ?? [];
  const raekkeKilder = [...new Set(raekker.map((r) => r.sourceId))];
  const pr_udgave = [...b.udgaver.map((u) => u.sourceId), null].map((valgt) => {
    const v = byggUdgaveFakta(faktaInput, valgt);
    const kilder = v.linjer.flatMap((l) => [...l.kilder, ...l.andre.map((a) => a.source)]).map((k) => k.label);
    const hovedKilde = valgt ?? (raekkeKilder.length === 1 ? raekkeKilder[0] : null);
    return {
      valgt, kilder, kunI: v.kunI.length,
      noter: hovedKilde ? b6Noter(raekker, hovedKilde) : [],
      noterKilde: hovedKilde ? b6Kilder(raekker, hovedKilde) : [], hovedKilde,
      linjer: hovedKilde ? linjerForUdgave(raekker, hovedKilde) : [],
    };
  });
  // Hovedets linjer som appen viser dem uden valgt udgave: skemalinjer, ellers de synlige lineage-navne.
  const linjeNavneFallback = (b.lineage.byPerson[focusId] ?? []).filter((lk) => !erTekniskLinje(lk)).map((lk) => b.lineage.navn[lk] ?? `Linje ${lk}`);
  return {
    medlemmer: [...medlemmer], chips: vaelger.chips.map((c) => c.label), chipUdgaver: vaelger.chips.map((c) => c.sourceId),
    faktaKilder: factRows.map((r) => factSource(r).label), buildPersonFactsKilder: buildPersonFacts(factRows)
      .flatMap((f) => [...(f.chosen ? [f.chosen] : []), ...f.others]).map((s) => s.source.label),
    pr_udgave, linjeNavneFallback,
    // Fakta mærkes direkte fra rækkens source_id; en række uden kilde er 'ingen' (aldrig null).
    faktaMedKilde: factRows.map((r) => ({ kilde: faktaKilde(r), tekst: factSource(r).label })),
    buildPersonFactsMedKilde: factRows.flatMap((r) => buildPersonFacts([r])
      .flatMap((f) => [...(f.chosen ? [f.chosen] : []), ...f.others]).map((st) => ({ kilde: faktaKilde(r), tekst: st.source.label }))),
    // byggUdgaveFakta giver kun etiketter; label → række-kilde, og en etiket med to forskellige kilder fejler højlydt.
    kildeAfFaktaLabel: (() => {
      const m = new Map<string, string>();
      for (const r of factRows) {
        const l = factSource(r).label;
        const k = faktaKilde(r);
        if (m.has(l) && m.get(l) !== k) throw new Error(`etiketten »${l}« hører til to kilder: ${m.get(l)} og ${k}`);
        m.set(l, k);
      }
      return m;
    })(),
    sources: sorterKilder(b.sourcesBy[focusId] ?? []), nummer: bogensNummer(b.sourcesBy, focusId),
    optraeder: optraederSom(b.sourcesBy[focusId] ?? []),
  };
}

type Mærket = { kilde: string | null; hvor: string; tekst: string };

// Kilde-id udledt af rækken (familiekildens udgavenavn slået op i udgaverne), aldrig af den viste tekst.
const faktaKilde = (r: PublicPersonFactRow): string => (r.source_id == null ? 'ingen' : String(r.source_id));

function familieKilderMedKilde(fase: Fase, b: Bygget): Mærket[] {
  return mapFamilieKilder(laes(fase, 'family_sources')).map((k) => ({
    kilde: b.udgaver.find((u) => u.label === k.sourceLabel)?.sourceId ?? null, hvor: 'familiekilde', tekst: kildeLinje(k),
  }));
}
function familieKilder(fase: Fase): string[] {
  return mapFamilieKilder(laes(fase, 'family_sources')).map(kildeLinje);
}

function provenienMedKilde(fase: Fase, focusId: string, b: Bygget): Mærket[] {
  const medlemmer = new Set((b.mergedFrom[focusId] ?? [{ personId: focusId }]).map((m) => String(m.personId)));
  const personAfAssert = new Map(laes<{ assertion_id: number; person_id: number }>(fase, 'fact_assertion')
    .filter((a) => medlemmer.has(String(a.person_id))).map((a) => [a.assertion_id, String(a.person_id)] as const));
  const kilde = new Map(laes<{ assertion_id: number; titel: string | null; udgave: string | null }>(fase, 'citation_source')
    .map((c) => [c.assertion_id, { titel: c.titel, udgave: c.udgave }] as const));
  const cits = laes<{ assertion_id: number; side: string | null; side_trykt?: string | null }>(fase, 'citation')
    .map((c) => ({ ...c, source: kilde.get(c.assertion_id) ?? null })) as unknown as RaaCitationRow[];
  const rows = citationRowsTilProveniens(cits, personAfAssert);
  const refs = buildProvenanceSources(rows, Object.fromEntries([...medlemmer].map((m) => [m, focusId])));
  const kildeAfVaerk = new Map(laes<RawSource>(fase, 'source').map((x) => [x.titel || x.udgave || '', String(x.id)] as const));
  expect(kildeAfVaerk.size, 'titel ?? udgave er unik pr. kilde').toBe(laes<RawSource>(fase, 'source').length);
  return (refs[focusId] ?? []).map((r) => ({ kilde: kildeAfVaerk.get(r.work) ?? null, hvor: `proveniens ${focusId}`, tekst: r.ref ? `${r.work}, ${r.ref}` : r.work }));
}
function proveniens(fase: Fase, focusId: string, b: Bygget): string[] {
  return provenienMedKilde(fase, focusId, b).map((m) => m.tekst);
}

// Alle visningsstrenge uden prosa. `kilde` er kilde-id'et (fra rækken, aldrig fra teksten) for strenge, der stammer fra
// én kilde; null for strenge uden kildetilhør (linjenavne). `hvor` bruges i fejlmeldingen.
function samlStrenge(fase: Fase, b: Bygget): Mærket[] {
  const ud: Mærket[] = [];
  const add = (kilde: string | null, hvor: string, tekst: string | null | undefined) => { if (tekst != null) ud.push({ kilde, hvor, tekst }); };
  for (const [pid, refs] of Object.entries(b.sourcesBy)) for (const r of refs) { const k = r.sourceId ?? null; add(k, `sourcesBy.ref ${pid}`, r.ref); add(k, `sourcesBy.kort ${pid}`, r.kort); add(k, `sourcesBy.work ${pid}`, r.work); }
  for (const pid of Object.keys(b.lineage.byPerson)) {
    for (const lk of b.lineage.byPerson[pid].filter((k) => !erTekniskLinje(k))) add(null, `linje ${pid}`, b.lineage.navn[lk] ?? `Linje ${lk}`);
  }
  for (const l of b.lineage.list) add(null, 'linje liste', l.navn ?? `Linje ${l.linje}`);
  for (const [pid, rs] of Object.entries(b.linjeRaekkerBy)) {
    for (const sid of new Set(rs.map((r) => r.sourceId))) {
      linjerForUdgave(rs, sid).forEach((t) => add(sid, `hoved ${pid}`, t));
      b6Noter(rs, sid).forEach((t, i) => add(b6Kilder(rs, sid)[i], `b6 ${pid}`, t));
    }
  }
  for (const f of [FOKUS_CONRAD, FOKUS_PLACERET]) {
    const v = visning(fase, b, f);
    v.chips.forEach((t, i) => add(v.chipUdgaver[i], `chip ${f}`, t));
    v.faktaMedKilde.forEach((m) => add(m.kilde, `faktakilde ${f}`, m.tekst));
    v.buildPersonFactsMedKilde.forEach((m) => add(m.kilde, `faktakilde(buildPersonFacts) ${f}`, m.tekst));
    v.pr_udgave.forEach((u) => {
      u.kilder.forEach((t) => add(v.kildeAfFaktaLabel.get(t) ?? null, `faktavisning ${f}`, t));
      u.noter.forEach((t, i) => add(u.noterKilde[i] ?? null, `b6 ${f}`, t));
      u.linjer.forEach((t) => add(u.hovedKilde, `hoved ${f}`, t));
    });
    v.linjeNavneFallback.forEach((t) => add(null, `hoved-fallback ${f}`, t));
    for (const sid of new Set((b.sourcesBy[f] ?? []).map((r) => r.sourceId ?? ''))) {
      add(sid, `optraeder ${f}`, optraederSom((b.sourcesBy[f] ?? []).filter((r) => r.sourceId === sid)));
    }
    provenienMedKilde(fase, f, b).forEach((m) => add(m.kilde, m.hvor, m.tekst));
  }
  familieKilderMedKilde(fase, b).forEach((m) => add(m.kilde, m.hvor, m.tekst));
  return ud;
}

// De andre kilder en B6-note handler om, i notens rækkefølge (samme regel som b6Noter).
function b6Kilder(raekker: LinjeRaekke[], valgt: string): string[] {
  const ud: string[] = [];
  for (const r of raekker) if (r.sourceId !== valgt && r.provenance === 'placement' && !ud.includes(r.sourceId)) ud.push(r.sourceId);
  return ud;
}

function sidetal(tekst: string): number[] {
  const ud: number[] = [];
  for (const m of tekst.matchAll(/\bs\.\s*(\d+)(?:\s*[-–]\s*(\d+))?/g)) { ud.push(Number(m[1])); if (m[2]) ud.push(Number(m[2])); }
  return ud;
}

describe.skipIf(!DIR)('trin 6e-2: klienten på data før og efter ceremonien', () => {
  const data = { foer: undefined as Bygget | undefined, efter: undefined as Bygget | undefined };
  const hent = (f: Fase) => (data[f] ??= byg(f));
  const vist: Record<string, unknown> = {};

  it('opslagene via udgavenavn og værk er entydige, og ingen mærkning mangler', () => {
    for (const f of ['foer', 'efter'] as Fase[]) {
      const src = laes<RawSource>(f, 'source');
      const udgaver = src.map((x) => x.udgave).filter((u): u is string => u != null);
      expect(new Set(udgaver).size, `${f}: source.udgave er unik`).toBe(udgaver.length);
      const vaerker = src.map((x) => x.titel || x.udgave || '');
      expect(new Set(vaerker).size, `${f}: titel ?? udgave er unik`).toBe(vaerker.length);
      const mangler = samlStrenge(f, hent(f)).filter((m) => m.kilde === null && !/^(linje|hoved-fallback) /.test(m.hvor));
      expect(mangler.map((m) => `${m.hvor}: ${m.tekst}`), `${f}: streng uden kilde`).toEqual([]);
    }
  });

  it('eksporten indeholder de tjekkede personer og foldningen er som forventet', () => {
    for (const f of ['foer', 'efter'] as Fase[]) {
      const b = hent(f);
      expect(b.canon['255'], f).toBe('392');
      expect(b.canon['1198'], f).toBe('392');
      expect(b.canon['1093'], f).toBe('149');
      expect([...(b.mergedFrom[FOKUS_CONRAD] ?? []).map((m) => m.personId)].sort(), f).toEqual(['1198', '255', '392']);
      expect([...(b.mergedFrom[FOKUS_PLACERET] ?? []).map((m) => m.personId)].sort(), f).toEqual(['1093', '149']);
    }
  });

  for (const fase of ['foer', 'efter'] as Fase[]) {
    describe(fase, () => {
      it('ingen teknisk etiket (record-, legacy-source:, »Linje 1939«) i nogen visningsstreng', () => {
        const fund = samlStrenge(fase, hent(fase)).filter((s) => FORBUDT.test(s.tekst));
        expect(fund.map((s) => `${s.hvor}: ${s.tekst}`)).toEqual([]);
      });

      it('linjelisten (slutreview I-1): hver synlig linje én gang, ingen teknisk nøgle, antal = filtrets træffere', () => {
        const b = hent(fase);
        const synlige = synligeLinjer(b.lineage.list);
        expect(synlige.length, 'ingen teknisk nøgle i listen').toBe(b.lineage.list.length);
        const navne = synlige.map((l) => l.navn);
        expect(navne.every((n) => n != null), navne.join(' | ')).toBe(true);
        expect(new Set(navne).size, `unikke navne: ${navne.join(' | ')}`).toBe(navne.length);
        const pr = kanoniskeLinjerPrPerson(b.lineage);
        for (const l of synlige) {
          expect(Object.keys(pr).filter((pid) => pr[pid].includes(l.linje)).length, `${l.navn}: træffere = antal`).toBe(l.count);
        }
        vist[`linjeliste_${fase}`] = synlige.map((l) => ({ navn: l.navn, antal: l.count, stamfader: l.headId }));
      });

      it('2018-20 for 392 viser V-1 i fakta- og chiptekster', () => {
        const b = hent(fase);
        const v = visning(fase, b, FOKUS_CONRAD);
        const chip = v.chips.filter((_, i) => v.chipUdgaver[i] === '1');
        expect(chip.some((t) => t.includes('V-1')), `chips ${chip.join(' | ')}`).toBe(true);
        const faktaKilder = v.pr_udgave.find((u) => u.valgt === '1')!.kilder;
        expect(faktaKilder.some((t) => t.includes('V-1')), `fakta ${[...new Set(faktaKilder)].join(' | ')}`).toBe(true);
      });
    });
  }

  describe('foer', () => {
    it('linjelisten er som før 6e-2: seks linjer med 2018-20s stamfædre og 1939-legacy-linjen VI', () => {
      const liste = synligeLinjer(hent('foer').lineage.list);
      expect(liste.length).toBe(6);
      expect(liste.map((l) => l.headId)).toEqual(['1', '137', '172', '298', '392', '1437']);
      expect(liste.map((l) => l.count)).toEqual([136, 35, 126, 84, 163, 26]);
    });

    it('Kilde i Aarbogen for 1198 er kun værket uden side; bogens nummer for Conrad er V, nr. 1', () => {
      const b = hent('foer');
      const refs = b.sourcesBy['392'].filter((r) => r.personId === '1198');
      expect(refs.length).toBe(1);
      expect(refs[0].work).toContain('DAA 1939');
      expect(refs[0].ref).toBe('');
      expect(refs[0].kort).toBe('');
      expect(bogensNummer(b.sourcesBy, FOKUS_CONRAD)).toBe('V, nr. 1');
    });

    it('ingen PDF-side i chips, familiekilder eller Kilde i Aarbogen for 1939', () => {
      const b = hent('foer');
      const udgave1939 = (t: string) => t.includes('1939');
      for (const f of [FOKUS_CONRAD, FOKUS_PLACERET]) {
        const v = visning('foer', b, f);
        for (const c of v.chips.filter(udgave1939)) expect(sidetal(c), `chip ${f}: ${c}`).toEqual([]);
        for (const r of v.sources.filter((x) => x.sourceId === '3')) expect(sidetal(`${r.ref} ${r.kort ?? ''}`), `kilde ${f}: ${r.ref}`).toEqual([]);
      }
      for (const t of familieKilder('foer').filter(udgave1939)) expect(sidetal(t), `familiekilde: ${t}`).toEqual([]);
      for (const [pid, refs] of Object.entries(b.sourcesBy)) {
        for (const r of refs.filter((x) => x.sourceId === '3')) expect(sidetal(`${r.ref} ${r.kort ?? ''}`), `kilde ${pid}: ${r.ref}`).toEqual([]);
      }
    });

    it('ingen B6-note og ingen 1939-placering i linjerækkerne', () => {
      const b = hent('foer');
      expect(b.linjeRaekkerBy[FOKUS_PLACERET]?.map((r) => r.sourceId)).toEqual(['1']);
      // Uden 1939-placering er der ingen note, når 2018-20 (eller ingen) er valgt; 1939-visningen kan kun sige, hvor 2018-20 placerer.
      expect(visning('foer', b, FOKUS_PLACERET).pr_udgave.filter((u) => u.valgt !== '3').flatMap((u) => u.noter)).toEqual([]);
      vist.foer = vistUdsnit('foer', b);
    });
  });

  describe('efter', () => {
    it('linjelisten samler udgaverne: samme seks linjer og stamfædre; 1939-personer findes under linjen', () => {
      const b = hent('efter');
      const foer = synligeLinjer(hent('foer').lineage.list);
      const liste = synligeLinjer(b.lineage.list);
      expect(liste.map((l) => [l.navn, l.headId])).toEqual(foer.map((l) => [l.navn, l.headId]));
      // En person, hvis eneste stamtavlerækker er fra 1939, findes under sin linje (filtret ser alle udgaver).
      const kilderPr = new Map<string, Set<string>>();
      for (const x of b.extIds) {
        if (!x.linje) continue;
        const pid = b.canon[String(x.person_id)] ?? String(x.person_id);
        const k = kilderPr.get(pid) ?? new Set<string>();
        k.add(String(x.source_id));
        kilderPr.set(pid, k);
      }
      const kun1939 = [...kilderPr].filter(([, k]) => k.size === 1 && k.has('3')).map(([pid]) => pid);
      const pr = kanoniskeLinjerPrPerson(b.lineage);
      const holsten = liste.find((l) => l.navn === 'Den holstenske linje')!;
      expect(kun1939.filter((pid) => pr[pid]?.includes(holsten.linje)).length).toBeGreaterThan(0);
      for (const l of liste) expect(l.count, l.navn ?? '').toBeGreaterThanOrEqual(foer.find((f) => f.navn === l.navn)!.count);
    });

    it('1198: fakta-kilden er DAA 1939, s. 52', () => {
      const rows = laes<PublicPersonFactRow>('efter', 'facts').filter((r) => String(r.person_id) === '1198');
      const labels = rows.map((r) => factSource(r).label);
      expect(labels.length).toBeGreaterThan(0);
      expect(labels).toContain('DAA 1939, s. 52');
      // De bundne fakta bærer postens sider (52-53); alt andet er sammen om side 52.
      for (const l of labels) expect(l, l).toMatch(/^DAA 1939, s\. 52(-53)?$/);
    });

    it('en placeret 1939-person har ref på formen »<romertal>. <navn>, s. <n>, nr. <n>«', () => {
      const b = hent('efter');
      const alle = Object.values(b.sourcesBy).flat().filter((r) => r.sourceId === '3');
      const former = alle.filter((r) => /^[IVXLC]+\. .+, s\. \d+, nr\. \d+$/.test(r.ref));
      expect(former.length).toBeGreaterThan(0);
      // Komponenten 1093/149 hører til dem (1093 er placeret i 1939).
      const mine = b.sourcesBy[FOKUS_PLACERET].filter((r) => r.sourceId === '3');
      expect(mine.map((r) => r.ref).some((r) => /^[IVXLC]+\. .+, s\. \d+, nr\. \d+$/.test(r)), mine.map((r) => r.ref).join(' | ')).toBe(true);
    });

    it('2018-20: ref for 392 er »V. Den grevelige linje af 1673, nr. 1« uden side; ingen »Kilde i Aarbogen«-ref eller bogens nummer for 2018-20 har »s. «', () => {
      const b = hent('efter');
      const mine = b.sourcesBy[FOKUS_CONRAD].filter((r) => r.sourceId === '1' && r.personId === '392');
      expect(mine.map((r) => r.ref)).toEqual(['V. Den grevelige linje af 1673, nr. 1']);
      // Kun »Kilde i Aarbogen« og bogens nummer for kilde 1; fakta og chips har bevidst »s. N · V-1«.
      const med = Object.entries(b.sourcesBy).flatMap(([pid, rs]) => rs.filter((r) => r.sourceId === '1' && (r.ref.includes('s. ') || (r.kort ?? '').includes('s. '))).map((r) => `${pid}: ${r.ref}`));
      expect(bogensNummer(b.sourcesBy, FOKUS_CONRAD)).not.toContain('s. ');
      expect(med).toEqual([]);
    });

    it('ingen 1939-sidetal over 92', () => {
      const b = hent('efter');
      const over = b.coords.filter((c) => String(c.source_id) === '3' && c.printed_page != null && Number(c.printed_page) > 92).map((c) => `${c.person_id}: ${c.printed_page}`);
      expect(over).toEqual([]);
      // Alle visningsstrenge med kilde 3 (kilden udledt af rækken): hvert sidetal skal være højst 92.
      const tal = samlStrenge('efter', b).filter((s) => s.kilde === '3')
        .flatMap((s) => sidetal(s.tekst).filter((n) => n > 92).map((n) => `${s.hvor}: ${n}`));
      expect(tal).toEqual([]);
      for (const r of Object.entries(b.sourcesBy).flatMap(([pid, rs]) => rs.filter((x) => x.sourceId === '3').map((x) => [pid, x] as const))) {
        expect(sidetal(r[1].ref).filter((n) => n > 92), `${r[0]}: ${r[1].ref}`).toEqual([]);
      }
    });

    it('B6-noten for 2018-20/1939-komponenten (149/1093) findes og har den rigtige form', () => {
      const b = hent('efter');
      const noter = visning('efter', b, FOKUS_PLACERET).pr_udgave.find((u) => u.valgt === '1')!.noter;
      expect(noter.length).toBeGreaterThan(0);
      expect(noter.every((n) => n.startsWith('✓ også i DAA 1939 (') || n.startsWith('DAA 1939 placerer i:')), noter.join(' | ')).toBe(true);
      vist.efter = vistUdsnit('efter', b);
      if (DIR) writeFileSync(join(DIR, 'vist-strenge.json'), JSON.stringify(vist, null, 1));
    });
  });
});

// Udsnit til rapporten: kun etiketter, sidetal og id'er.
function vistUdsnit(fase: Fase, b: Bygget) {
  const ud: Record<string, unknown> = {};
  for (const f of [FOKUS_CONRAD, FOKUS_PLACERET]) {
    const v = visning(fase, b, f);
    ud[f] = {
      medlemmer: v.medlemmer.sort(), chips: v.chips, bogensNummer: v.nummer,
      kildeIAarbogen: v.sources.map((r) => ({ person: r.personId, work: r.work, ref: r.ref, kort: r.kort })),
      optraederSom: v.optraeder,
      faktakilder: [...new Set(v.faktaKilder)].sort(),
      faktaVisningKilder: Object.fromEntries(v.pr_udgave.map((u) => [String(u.valgt), [...new Set(u.kilder)].sort()])),
      hovedLinjer: Object.fromEntries(v.pr_udgave.map((u) => [String(u.valgt), u.linjer])),
      b6: Object.fromEntries(v.pr_udgave.map((u) => [String(u.valgt), u.noter])),
      linjeNavneFallback: v.linjeNavneFallback,
      proveniensFraCitation: proveniens(fase, f, b),
    };
  }
  ud.familiekilder = familieKilder(fase);
  const p1198 = laes<PublicPersonFactRow>(fase, 'facts').filter((r) => String(r.person_id) === '1198').map((r) => factSource(r).label);
  ud.faktakilder1198 = [...new Set(p1198)].sort();
  return ud;
}

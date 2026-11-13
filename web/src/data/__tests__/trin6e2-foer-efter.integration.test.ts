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
  type AppPerson, type PublicCoordinateRow, type PublicPersonFactRow, type RaaCitationRow, type UdgaveFaktaInput,
} from '@daa/core';
import { factSource } from '../../../../packages/core/src/personFacts';
import { buildLineage, erTekniskLinje, stamtavleSkemaOpslag, type LineageSchemeRows } from '../lineage';
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
  const lineage = buildLineage(extIds, lineageRows, canon, schemeRows);
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
    sources: sorterKilder(b.sourcesBy[focusId] ?? []), nummer: bogensNummer(b.sourcesBy, focusId),
    optraeder: optraederSom(b.sourcesBy[focusId] ?? []),
  };
}

function familieKilder(fase: Fase): string[] {
  return mapFamilieKilder(laes(fase, 'family_sources')).map(kildeLinje);
}

function proveniens(fase: Fase, focusId: string, b: Bygget): string[] {
  const medlemmer = new Set((b.mergedFrom[focusId] ?? [{ personId: focusId }]).map((m) => String(m.personId)));
  const personAfAssert = new Map(laes<{ assertion_id: number; person_id: number }>(fase, 'fact_assertion')
    .filter((a) => medlemmer.has(String(a.person_id))).map((a) => [a.assertion_id, String(a.person_id)] as const));
  const kilde = new Map(laes<{ assertion_id: number; titel: string | null; udgave: string | null }>(fase, 'citation_source')
    .map((c) => [c.assertion_id, { titel: c.titel, udgave: c.udgave }] as const));
  const cits = laes<{ assertion_id: number; side: string | null; side_trykt?: string | null }>(fase, 'citation')
    .map((c) => ({ ...c, source: kilde.get(c.assertion_id) ?? null })) as unknown as RaaCitationRow[];
  const rows = citationRowsTilProveniens(cits, personAfAssert);
  const refs = buildProvenanceSources(rows, Object.fromEntries([...medlemmer].map((m) => [m, focusId])));
  return (refs[focusId] ?? []).map((r) => (r.ref ? `${r.work}, ${r.ref}` : r.work));
}

// Alle visningsstrenge uden prosa, hver med en kilde-etiket til fejlmeldingen.
function samlStrenge(fase: Fase, b: Bygget): { hvor: string; tekst: string }[] {
  const ud: { hvor: string; tekst: string }[] = [];
  const add = (hvor: string, tekst: string | null | undefined) => { if (tekst != null) ud.push({ hvor, tekst }); };
  for (const [pid, refs] of Object.entries(b.sourcesBy)) for (const r of refs) { add(`sourcesBy.ref ${pid}`, r.ref); add(`sourcesBy.kort ${pid}`, r.kort); add(`sourcesBy.work ${pid}`, r.work); }
  for (const pid of Object.keys(b.lineage.byPerson)) {
    for (const lk of b.lineage.byPerson[pid].filter((k) => !erTekniskLinje(k))) add(`linje ${pid}`, b.lineage.navn[lk] ?? `Linje ${lk}`);
  }
  for (const [pid, rs] of Object.entries(b.linjeRaekkerBy)) {
    for (const sid of new Set(rs.map((r) => r.sourceId))) { linjerForUdgave(rs, sid).forEach((t) => add(`hoved ${pid}`, t)); b6Noter(rs, sid).forEach((t) => add(`b6 ${pid}`, t)); }
  }
  for (const f of [FOKUS_CONRAD, FOKUS_PLACERET]) {
    const v = visning(fase, b, f);
    v.chips.forEach((t) => add(`chip ${f}`, t));
    v.faktaKilder.forEach((t) => add(`faktakilde ${f}`, t));
    v.buildPersonFactsKilder.forEach((t) => add(`faktakilde(buildPersonFacts) ${f}`, t));
    v.pr_udgave.forEach((u) => { u.kilder.forEach((t) => add(`faktavisning ${f}`, t)); u.noter.forEach((t) => add(`b6 ${f}`, t)); u.linjer.forEach((t) => add(`hoved ${f}`, t)); });
    v.linjeNavneFallback.forEach((t) => add(`hoved-fallback ${f}`, t));
    add(`optraeder ${f}`, v.optraeder);
    proveniens(fase, f, b).forEach((t) => add(`proveniens ${f}`, t));
  }
  familieKilder(fase).forEach((t) => add('familiekilde', t));
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
        for (const r of v.sources.filter((x) => x.work.includes('1939'))) expect(sidetal(`${r.ref} ${r.kort ?? ''}`), `kilde ${f}: ${r.ref}`).toEqual([]);
      }
      for (const t of familieKilder('foer').filter(udgave1939)) expect(sidetal(t), `familiekilde: ${t}`).toEqual([]);
      for (const [pid, refs] of Object.entries(b.sourcesBy)) {
        for (const r of refs.filter((x) => x.work.includes('1939'))) expect(sidetal(`${r.ref} ${r.kort ?? ''}`), `kilde ${pid}: ${r.ref}`).toEqual([]);
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

    it('2018-20: ref for 392 er »V. Den grevelige linje af 1673, nr. 1« uden side; ingen 2018-20-ref har »s. «', () => {
      const b = hent('efter');
      const mine = b.sourcesBy[FOKUS_CONRAD].filter((r) => r.sourceId === '1' && r.personId === '392');
      expect(mine.map((r) => r.ref)).toEqual(['V. Den grevelige linje af 1673, nr. 1']);
      const med = Object.entries(b.sourcesBy).flatMap(([pid, rs]) => rs.filter((r) => r.sourceId === '1' && (r.ref.includes('s. ') || (r.kort ?? '').includes('s. ')).valueOf()).map((r) => `${pid}: ${r.ref}`));
      expect(med).toEqual([]);
    });

    it('ingen 1939-sidetal over 92', () => {
      const b = hent('efter');
      const over = b.coords.filter((c) => String(c.source_id) === '3' && c.printed_page != null && Number(c.printed_page) > 92).map((c) => `${c.person_id}: ${c.printed_page}`);
      expect(over).toEqual([]);
      const tal = samlStrenge('efter', b).filter((s) => s.tekst.includes('1939') || /^(sourcesBy|hoved|b6)/.test(s.hvor) === false ? s.tekst.includes('1939') : false)
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

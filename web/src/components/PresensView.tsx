// Præsensliste-læsefladen (spec 2026-07-22 §6). Redaktion-gated i v1: klient-gaten er UX —
// RLS er sikkerhedsgrænsen (§8). Beregningen er en ren projektion; ingen skrivninger.
import { useEffect, useMemo, useState } from 'react';
import { buildPresensListe, fmtSkilt, kanoniserPresensGrundlag, groupByLinje, parSkilsmisse, samlIds } from '@daa/core';
import type { Model, PresensGren, PresensListe, PresensNode, PresensLinjeGruppe } from '@daa/core';
import {
  fetchPresensGrundlag, fetchPresensNavneDele, formatAnkerNavn, formatAndetNavn,
  type PresensGrundlag, type PresensNavneDele,
} from '../data/presens';
import { fetchPresensLinjer, fetchPresensIntro, type PresensLinjeInfo } from '../data/presensLinjer';
import { fetchPersonDetail } from '../data/public';
import { personMemberIds } from '../data/personMembers';
import { currentSession, type RedSession } from '../data/auth';
import { NarrativRenderer } from './NarrativRenderer';
import { Tilstand, tilstandPrimaer, tilstandSekundaer } from './Tilstand';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath } from '../data/nav';
import { SignedImg } from './SignedImg';

// Ren gren-sektion — eksporteret til test. navnAf/aarAf holder Model ude af renderingen.
// navnAfAnker (valgfri, default=navnAf) navngiver KUN grenens hovedrække (dybde 0, gren.ankerBlok)
// efter bogens hovedrække-format (fulde fornavne + titel inde i navnet + efternavn); alle øvrige
// rækker (søskende, efterkommere, forbindelsesled, partnere) bruger det almindelige navnAf-format
// (Titel + fornavne, uden efternavn) — jf. mekanismen fundet ved bruger-verifikation 2026-07-24.
//
// erAaben/erHenter/bioAf/bioFejlAf/onToggle (alle valgfri, default = ingen fold-ud nogensinde åben) styrer
// fold-ud-narrativet ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md). Komponenten
// kender bevidst IKKE til fetchPersonDetail — al hentning/cache lever i PresensView, der kalder
// onToggle og læser tilbage via erAaben/erHenter/bioAf. Det holder denne fil testbar uden supabase.
export function PresensGrenSektion(props: {
  gren: PresensGren;
  navnAf: (id: string) => string;
  navnAfAnker?: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  erAaben?: (id: string) => boolean;
  erHenter?: (id: string) => boolean;
  bioAf?: (id: string) => string | undefined;
  bioFejlAf?: (id: string) => string | undefined;
  onToggle?: (id: string) => void;
  fokusId?: string | null;
}) {
  const {
    gren, navnAf, navnAfAnker = navnAf, aarAf, onPick,
    erAaben = () => false, erHenter = () => false, bioAf = () => undefined, bioFejlAf = () => undefined, onToggle = () => {},
    fokusId,
  } = props;

  // Fold-ud-boksen under en række — bio-teksten rendres med samme NarrativRenderer som Om-siden/
  // Godser/detaljepanelet (samme typografi, samme klikbare person-links INDE i teksten, som fortsat
  // navigerer direkte via onPick — det er en anden, allerede etableret mekanik, ikke en del af dette
  // fold-ud-lag). "Se fuld profil" er den eneste tilbageværende vej fra Præsenslisten til profilen.
  const renderFoldud = (id: string) => (
    <div style={{ marginTop: 4, marginBottom: 12, paddingLeft: 14, borderLeft: '2px solid rgba(185,160,106,.45)' }}>
      {erHenter(id) ? (
        <div style={{ fontSize: 14, color: T.inkMuted }}>Henter…</div>
      ) : (
        <>
          <div style={{ fontFamily: T.serif, fontSize: 16.5, lineHeight: 1.6, color: T.inkSecondary }}>
            {bioFejlAf(id) ? (
              <span role="alert" style={{ color: T.bordeaux }}>Kunne ikke hente biografien: {bioFejlAf(id)}</span>
            ) : bioAf(id) ? (
              <NarrativRenderer tekst={bioAf(id)!} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.inkMuted} />
            ) : (
              <span style={{ fontStyle: 'italic', color: T.inkMuted }}>Ingen biografi registreret</span>
            )}
          </div>
          <Link
            href={personPath(id)}
            onNavigate={() => onPick(id)}
            style={{ marginTop: 6, display: 'block', color: T.bordeaux, fontSize: 13.5, fontFamily: T.mono, letterSpacing: '.03em' }}
          >
            → Se fuld profil
          </Link>
        </>
      )}
    </div>
  );
  // dybde styrer KUN den visuelle indrykning (marginLeft); erAnker styrer navngivningsformatet
  // og er sand PRÆCIST for gren.ankerBlok's egen række — de to var tidligere sammenblandet via
  // "dybde===0", hvilket fejlagtigt gav grupperødder (fx "Søstre") anker-navneformat, når de blev
  // rykket til dybde 0 (bruger-fund 2026-07-24: grupperødder står allerede under egen overskrift
  // og skal derfor IKKE indrykkes yderligere, men skal stadig hedde "Komtesse X", ikke ankerformen).
  //
  // marginLeft er en FAST værdi pr. niveau (0 for roden, ellers 22 — samme indent*22 som
  // mockuppets egen padding-left, jf. Reventlow-praesens.dc.html linje 170), IKKE dybde*22 — børnene
  // renderes som nestede <div>'er (bruger-fund 2026-07-24: afstanden mellem generationer voksede
  // støt jo dybere i træet, fx en 4-5 led lang linje som "Farfars farbror"). Da marginLeft på et
  // nested element regnes relativt til FORÆLDRENS allerede forskudte position, ville dybde*22 lægge
  // barnets fulde absolutte forskydning oveni forælderens — dybde 2 endte fx 66px fra venstre
  // (22 fra forælder + 44 egen), ikke de tilsigtede 44. Nestingen giver akkumuleringen gratis; et
  // fast 22px-tillæg pr. niveau giver derfor korrekt lineær 22/44/66/88-forskydning, som i mockuppet.
  //
  // Navne-spannet indeholder chevronen i sit EGET nested <span> og navnet i sit EGET nested <span>
  // (adskilt fra chevronen) — så det ydre klik-spans textContent er "▸ Navn", men det INDRE
  // navne-span's egen textContent forbliver PRÆCIST "Navn". Det er bevidst: getByText matcher på et
  // elements EGEN textContent, så hvis chevronen lå som ren tekst ved siden af navnet i samme span
  // (uden eget wrapper), ville alle eksisterende getByText('Anker Person')-agtige tests knække.
  const renderNode = (n: PresensNode, dybde: number, erAnker: boolean) => (
    <div key={n.id} style={{ marginLeft: dybde === 0 ? 0 : 22, marginBottom: 2, fontSize: 15.5, lineHeight: 1.5 }}>
      <span
        data-person-id={n.id}
        onClick={() => onToggle(n.id)}
        title={n.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
        style={{
          cursor: 'pointer',
          fontWeight: n.forbindelsesled ? 400 : 600, // bogens fed for levende, normal for forbindelsesled
          fontStyle: n.forbindelsesled ? 'italic' : 'normal', // bogens kursiv for afdøde forbindelsesled
          color: n.forbindelsesled ? T.inkMuted : T.ink,
          background: fokusId === n.id ? 'rgba(128,0,32,.08)' : 'transparent',
        }}
      >
        <span aria-hidden style={{ color: T.inkMuted, fontSize: 11 }}>{erAaben(n.id) ? '▾ ' : '▸ '}</span>
        <span>{erAnker ? navnAfAnker(n.id) : navnAf(n.id)}</span>
      </span>
      {' '}<span style={{ fontFamily: T.mono, fontSize: 12, color: T.inkMuted }}>{aarAf(n.id)}</span>
      {n.usikker ? <span style={{ color: T.goldInk }}> ⚠</span> : ''}
      {n.krydsReference ? <span style={{ fontSize: 13, color: T.inkMuted }}> ↗ vist andetsteds i denne gren</span> : ''}
      {n.partnere.filter((p) => p.levende || !n.forbindelsesled).map((p) => (
        <span key={p.id}>
          <span style={{ color: T.inkMuted, fontSize: 14.5 }}> · g. m. </span>
          <span data-person-id={p.id} onClick={() => onToggle(p.id)} style={{ cursor: 'pointer', color: T.inkMuted, fontSize: 14.5 }}>
            <span aria-hidden style={{ fontSize: 10 }}>{erAaben(p.id) ? '▾ ' : '▸ '}</span>
            <span>{navnAf(p.id)}</span>
          </span>
          {p.skilsmisse && <span style={{ color: T.inkMuted, fontSize: 14.5 }}>{`, ${fmtSkilt(p.skilsmisse, 'aar')}`}</span>}
        </span>
      ))}
      {erAaben(n.id) && renderFoldud(n.id)}
      {n.partnere.filter((p) => erAaben(p.id)).map((p) => <div key={`fu-${p.id}`}>{renderFoldud(p.id)}</div>)}
      {n.boern.map((b) => renderNode(b, dybde + 1, false))}
    </div>
  );
  return (
    <section
      id={gren.anker.gren != null ? `${gren.anker.linje.toLowerCase()}-g${gren.anker.gren}` : undefined}
      style={
        gren.anker.gren != null
          ? { marginTop: 34, borderLeft: '2px solid rgba(185,160,106,.45)', paddingLeft: 26 }
          : { marginBottom: 34 }
      }
    >
      {gren.anker.gren != null && (
        // margin:0 — appen har ingen CSS-reset, så <h2> ellers arver browserens UA-standardmargin
        // og lægger uventet luft oveni sektionens egen border-top/padding-top (reviewfund).
        <h2 style={{ margin: 0, fontFamily: T.mono, fontSize: 11.5, letterSpacing: '.22em', textTransform: 'uppercase', color: T.goldInk, fontWeight: 500 }}>
          {gren.anker.gren}. gren
        </h2>
      )}
      {renderNode(gren.ankerBlok, 0, true)}
      {gren.grupper.map((gr) => (
        <div key={gr.overskrift + gr.niveau} style={{ marginTop: 26 }}>
          <h3
            title={gr.usikker ? 'Usikkert slægtskab (formodet/omstridt led)' : undefined}
            // margin:0 (samme reviewfund) — kun paddingBottom+marginBottom fra mockuppet skal gælde,
            // ikke <h3>'ens egen UA-standard top-margin oveni det omgivende div's marginTop:26.
            style={{ margin: 0, fontFamily: T.mono, fontSize: 11, letterSpacing: '.2em', textTransform: 'uppercase', color: T.inkMuted, borderBottom: '1px solid rgba(34,31,26,.08)', paddingBottom: 6, marginBottom: 10 }}
          >
            {gr.overskrift}{gr.usikker ? ' ⚠' : ''}
          </h3>
          {/* dybde 0 — gruppens egen overskrift (fx "Søstre") giver allerede konteksten, så
              rødderne rykkes ikke yderligere ind (bruger-fund 2026-07-24). */}
          {gr.roedder.map((r) => renderNode(r, 0, false))}
        </div>
      ))}
    </section>
  );
}

// Pr.-linje sektion: våben + linjenummer + titel (lineage.navn) + navn (lineage.slaegtsnavn),
// derefter dens grene i rækkefølge (eksporteret til test, samme mønster som PresensGrenSektion).
export function PresensLinjeSektion(props: {
  gruppe: PresensLinjeGruppe;
  info: PresensLinjeInfo | undefined;
  navnAf: (id: string) => string;
  navnAfAnker?: (id: string) => string;
  aarAf: (id: string) => string;
  onPick: (id: string) => void;
  erAaben?: (id: string) => boolean;
  erHenter?: (id: string) => boolean;
  bioAf?: (id: string) => string | undefined;
  bioFejlAf?: (id: string) => string | undefined;
  onToggle?: (id: string) => void;
  fokusId?: string | null;
}) {
  const { gruppe, info, navnAf, navnAfAnker, aarAf, onPick, erAaben, erHenter, bioAf, bioFejlAf, onToggle, fokusId } = props;
  return (
    <div id={`linje-${gruppe.linje.toLowerCase()}`} style={{ marginTop: 52 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 24, borderTop: `1px solid rgba(34,31,26,.14)`, paddingTop: 26 }}>
        {info?.vaaben?.url && (
          <SignedImg src={info.vaaben.url} alt={info.vaaben.altTekst || 'Linjens våben'} style={{ width: 92, height: 'auto', display: 'block', flex: 'none' }} />
        )}
        <div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <span style={{ fontFamily: T.serif, fontSize: 34, fontWeight: 600, color: T.bordeaux, lineHeight: 1 }}>{gruppe.linje}</span>
            <span style={{ fontFamily: T.mono, fontSize: 12, letterSpacing: '.26em', textTransform: 'uppercase', color: T.ink }}>linje</span>
          </div>
          {info?.titel && (
            <div style={{ fontFamily: T.serif, fontSize: 19, fontStyle: 'italic', color: T.inkSecondary, marginTop: 8 }}>{info.titel}</div>
          )}
          {info?.slaegtsnavn && (
            <div style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.3em', textTransform: 'uppercase', color: T.inkMuted, marginTop: 6 }}>{info.slaegtsnavn}</div>
          )}
        </div>
      </div>
      {gruppe.grene.map((g) => (
        <PresensGrenSektion key={g.anker.personId} gren={g} navnAf={navnAf} navnAfAnker={navnAfAnker} aarAf={aarAf} onPick={onPick} erAaben={erAaben} erHenter={erHenter} bioAf={bioAf} bioFejlAf={bioFejlAf} onToggle={onToggle} fokusId={fokusId} />
      ))}
    </div>
  );
}

export default function PresensView(props: {
  model: Model | null; onPickPerson: (id: string) => void;
  // Følgesvends session (så login i dens dialog slår igennem her). Udeladt → visningen henter selv.
  session?: RedSession | null | 'henter'; onLogin?: () => void; onGoTree?: () => void;
}) {
  const { model, onPickPerson, onLogin, onGoTree } = props;
  const [egenSession, setEgenSession] = useState<RedSession | null | 'henter'>('henter');
  const session = props.session !== undefined ? props.session : egenSession;
  const [grundlag, setGrundlag] = useState<PresensGrundlag | null>(null);
  const [fejl, setFejl] = useState<string | null>(null);
  const [linjeInfo, setLinjeInfo] = useState<Record<string, PresensLinjeInfo>>({});
  const [intro, setIntro] = useState<string | null>(null);
  const [navneDele, setNavneDele] = useState<Record<string, PresensNavneDele>>({});
  // Fold-ud-narrativ ved navneklik (spec 2026-07-24-praesens-navn-foldud-design.md): aabne = hvilke
  // person-id'er er foldet ud; bioById = hentet bio-tekst pr. id (tom streng er en gyldig "ingen
  // bio"-værdi, IKKE "endnu ikke hentet" — den skelnen holdes af hentendeIds i stedet); hentendeIds =
  // id'er hvis fetchPersonDetail-kald er undervejs (viser "Henter…", og forhindrer dobbelt-hentning).
  const [aabne, setAabne] = useState<Set<string>>(new Set());
  const [bioById, setBioById] = useState<Map<string, string>>(new Map());
  const [bioFejlById, setBioFejlById] = useState<Map<string, string>>(new Map());
  const [hentendeIds, setHentendeIds] = useState<Set<string>>(new Set());
  const fokusId = (window.history.state as { fokusId?: string } | null)?.fokusId ?? null;

  const selvHenter = props.session === undefined;
  useEffect(() => { if (selvHenter) currentSession().then(setEgenSession).catch(() => setEgenSession(null)); }, [selvHenter]);
  useEffect(() => {
    if (session === 'henter' || session?.role !== 'redaktion') return;
    fetchPresensGrundlag().then(setGrundlag).catch((e) => setFejl(String(e?.message ?? e)));
    fetchPresensLinjer().then(setLinjeInfo).catch(() => setLinjeInfo({})); // ikke-kritisk pynt
    fetchPresensIntro().then(setIntro).catch(() => setIntro(null)); // ikke-kritisk pynt
  }, [session]);

  const liste: PresensListe | null = useMemo(() => {
    if (!model || !grundlag) return null;
    const k = kanoniserPresensGrundlag(model, grundlag.ankre, grundlag.levendeById);
    return buildPresensListe(model, k.ankre, k.levendeById);
  }, [model, grundlag]);

  const linjer = useMemo(() => (liste ? groupByLinje(liste.grene) : []), [liste]);

  // Alle person-id'er der reelt optræder i listen — bruges til at hente navne-dele (visning_navn/
  // visning_titel/visning_efternavn) til bogens to navngivningsformater (§ navnAf/navnAfAnker).
  const alleIds = useMemo(() => {
    if (!liste) return [] as string[];
    const s = new Set<string>();
    for (const g of liste.grene) {
      samlIds(g.ankerBlok, s);
      for (const gr of g.grupper) for (const r of gr.roedder) samlIds(r, s);
    }
    return [...s];
  }, [liste]);

  useEffect(() => {
    if (!alleIds.length) return;
    // Skilte par (model.skilsmisser via parSkilsmisse, pr. par på tværs af familier; null/manglende = ukendt → ingen
    // ægtefælle-titel, fail-closed).
    const erSkiltPar = model == null || model.skilsmisser == null ? null : (a: string, b: string) => parSkilsmisse(model, a, b) != null;
    fetchPresensNavneDele(alleIds, erSkiltPar).then(setNavneDele).catch(() => setNavneDele({})); // ikke-kritisk pynt
  }, [alleIds, model]);

  useEffect(() => {
    if (liste && fokusId) document.querySelector(`[data-person-id="${fokusId}"]`)?.scrollIntoView({ block: 'center' });
  }, [liste, fokusId]);

  if (session === 'henter') return <div style={{ padding: 40, color: T.inkMuted }}>Henter…</div>;
  // Listen viser levende og kan i dag kun ses af redaktionen (webredesign fase 0; medlemmer får
  // adgang i fase 8). Teksten siger, hvad der faktisk gælder, også for et indlogget medlem.
  if (session?.role !== 'redaktion') {
    const tilStamtrae = onGoTree && <button type="button" onClick={onGoTree} style={tilstandSekundaer}>Se stamtræet i stedet</button>;
    return (
      <div style={{ padding: 40 }}>
        {session ? (
          <Tilstand etiket="Kun for redaktionen" titel="Præsenslisten er ikke åben for medlemmer endnu" handlinger={tilStamtrae}>
            Den viser slægtens nulevende. Indtil reglerne for levende personer er på plads, kan den kun ses af redaktionen.
          </Tilstand>
        ) : (
          <Tilstand etiket="Kræver login" titel="Præsenslisten er ikke offentlig"
            handlinger={<>{onLogin && <button type="button" onClick={onLogin} style={tilstandPrimaer}>Log ind</button>}{tilStamtrae}</>}>
            Den viser slægtens nulevende og kan indtil videre kun ses af redaktionen.
          </Tilstand>
        )}
      </div>
    );
  }
  if (fejl) return <div style={{ padding: 40, color: T.bordeaux }}>Kunne ikke hente grundlaget: {fejl}</div>;
  if (!liste) return <div style={{ padding: 40, color: T.inkMuted }}>Henter…</div>;
  if (liste.grene.length === 0)
    return <div style={{ padding: 40, color: T.inkMuted, fontFamily: T.sans }}>
      Ingen overhoveder udpeget endnu. Udpeg et linje-/gren-overhoved via person-editorens felt
      "Overhoved (linje/gren)" (værdi fx "II linje, 1. gren").
      {Object.values(grundlag?.levendeById ?? {}).every((v) => !v) && (
        <div style={{ marginTop: 10 }}>Bemærk: modellen indeholder ingen levende personer — er du logget ind som redaktør, så genindlæs siden, så data hentes med dit login.</div>
      )}
    </div>;

  const fallbackNavn = (id: string) => model!.byId[id]?.name ?? `person ${id}`;
  const navnAf = (id: string) => formatAndetNavn(navneDele[id], fallbackNavn(id));
  const navnAfAnker = (id: string) => formatAnkerNavn(navneDele[id], fallbackNavn(id));
  const aarAf = (id: string) => model!.byId[id]?.years ?? '';
  const erAaben = (id: string) => aabne.has(id);
  const erHenter = (id: string) => hentendeIds.has(id);
  const bioAf = (id: string) => bioById.get(id);
  const bioFejlAf = (id: string) => bioFejlById.get(id);
  const onToggle = (id: string) => {
    const wasOpen = aabne.has(id);
    setAabne((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
    if (wasOpen) return;
    if (bioById.has(id) || hentendeIds.has(id)) return;
    setHentendeIds((prev) => new Set(prev).add(id));
    setBioFejlById((prev) => { const next = new Map(prev); next.delete(id); return next; });
    const members = personMemberIds(id, model!.byId[id]);
    fetchPersonDetail(id, members, false, { udgaver: model!.udgaver ?? [], udgaveForPersonRaekke: model!.udgaveForPersonRaekke ?? {} })
      .then((d) => setBioById((prev) => new Map(prev).set(id, d.bio)))
      .catch((e) => setBioFejlById((prev) => new Map(prev).set(id, String((e as Error)?.message ?? e))))
      .finally(() => setHentendeIds((prev) => { const next = new Set(prev); next.delete(id); return next; }));
  };
  return (
    <div style={{ maxWidth: 1240, margin: '0 auto', padding: '40px 28px 90px', display: 'grid', gridTemplateColumns: '200px minmax(0,860px)', gap: 36, justifyContent: 'center', alignItems: 'start' }}>
      {/* Venstre sticky-indeks */}
      <nav style={{ position: 'sticky', top: 28, paddingTop: 10 }}>
        <div style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.inkMuted, marginBottom: 14 }}>Indhold</div>
        {linjer.map((lin) => (
          <div key={lin.linje} style={{ marginBottom: 18 }}>
            <a href={`#linje-${lin.linje.toLowerCase()}`} style={{ display: 'flex', alignItems: 'baseline', gap: 8, color: T.ink }}>
              <span style={{ fontFamily: T.serif, fontSize: 19, fontWeight: 600, color: T.bordeaux }}>{lin.linje}</span>
              <span style={{ fontSize: 13.5, fontWeight: 600 }}>linje</span>
            </a>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 5, margin: '8px 0 0 4px', borderLeft: '1px solid rgba(34,31,26,.12)', paddingLeft: 14 }}>
              {lin.grene.filter((g) => g.anker.gren != null).map((g) => (
                <a key={g.anker.personId} href={`#${lin.linje.toLowerCase()}-g${g.anker.gren}`} style={{ fontSize: 13.5, color: T.inkMuted }}>
                  {g.anker.gren}. gren
                </a>
              ))}
            </div>
          </div>
        ))}
        <div style={{ borderTop: '1px solid rgba(34,31,26,.12)', marginTop: 6, paddingTop: 14 }}>
          <div style={{ fontFamily: T.mono, fontSize: 10.5, letterSpacing: '.2em', textTransform: 'uppercase', color: T.inkMuted, marginBottom: 10 }}>Signatur</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 7, fontSize: 12.5, color: T.inkMuted, lineHeight: 1.45 }}>
            <div><span style={{ fontWeight: 600, color: T.ink }}>Navn</span> — levende person</div>
            <div><span style={{ fontStyle: 'italic', color: T.inkMuted }}>Navn</span> — afdød forbindelsesled</div>
            <div><span style={{ color: T.goldInk }}>⚠</span> usikkert slægtskabsled</div>
            <div><span style={{ color: T.inkMuted }}>↗</span> vist andetsteds i grenen</div>
          </div>
        </div>
      </nav>

      {/* Arket */}
      <div style={{ minWidth: 0 }}>
        <div style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.12em', color: T.inkMuted, margin: '0 0 14px 4px' }}>Reventlow / Præsensliste</div>
        <div style={{ background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: 4, boxShadow: '0 2px 14px rgba(34,31,26,.07)', padding: '56px 72px 64px' }}>
          <div style={{ textAlign: 'center' }}>
            {/* Slægtens grundvåben er bevidst ikke vist her endnu — en linje-specifik
                coat_of_arms-række må ikke fejlagtigt genbruges som "hele slægtens" våben;
                kræver sin egen, adskillelige familie-niveau-række (jf. runbook-mønsteret). */}
            <div style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.22em', textTransform: 'uppercase', color: T.inkMuted }}>Slægten Reventlow</div>
            <h1 style={{ fontFamily: T.serif, fontSize: 40, fontWeight: 500, lineHeight: 1.08, margin: '12px 0 0' }}>Præsensliste</h1>
            <div style={{ fontSize: 14.5, color: T.inkMuted, marginTop: 10 }}>Slægtens nulevende medlemmer, ordnet efter linje og gren</div>
            <div style={{ width: 44, height: 1.5, background: T.gold, margin: '26px auto 0' }} />
          </div>

          {intro && (
            <div style={{ maxWidth: 640, margin: '34px auto 0' }}>
              {intro.split('\n\n').map((afsnit, i) => (
                <p key={i} style={{ fontFamily: T.serif, fontSize: 17.5, fontStyle: 'italic', lineHeight: 1.65, color: T.inkSecondary, margin: i === 0 ? 0 : '16px 0 0' }}>{afsnit}</p>
              ))}
            </div>
          )}

          {liste.advarsler.length > 0 && (
            <details style={{ margin: '28px auto 0', maxWidth: 640, background: T.surfaceGround, border: '1px solid rgba(185,160,106,.4)', borderRadius: 4, padding: '12px 18px' }}>
              <summary style={{ fontFamily: T.mono, fontSize: 11.5, letterSpacing: '.1em', color: T.inkMuted }}>
                {liste.advarsler.length} redaktionelle advarsler — rapportering, udløser aldrig ændringer
              </summary>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 12, fontSize: 13.5, color: T.inkMuted, lineHeight: 1.5 }}>
                {liste.advarsler.slice(0, 200).map((a, i) => (
                  <div key={i} style={{ display: 'flex', gap: 10 }}><span style={{ color: T.goldInk, flex: 'none' }}>▲</span><span>{a.besked}</span></div>
                ))}
              </div>
            </details>
          )}

          {linjer.map((lin) => (
            <PresensLinjeSektion key={lin.linje} gruppe={lin} info={linjeInfo[lin.linje]} navnAf={navnAf} navnAfAnker={navnAfAnker} aarAf={aarAf} onPick={onPickPerson} erAaben={erAaben} erHenter={erHenter} bioAf={bioAf} bioFejlAf={bioFejlAf} onToggle={onToggle} fokusId={fokusId} />
          ))}

          <div style={{ fontFamily: T.mono, fontSize: 11, letterSpacing: '.08em', color: T.inkMuted, marginTop: 52, borderTop: '1px solid rgba(34,31,26,.08)', paddingTop: 14, textAlign: 'center' }}>
            Kun levende personer samt afdøde forbindelsesled medtages.
          </div>
        </div>
      </div>
    </div>
  );
}

// ---- Person-detalje (højre panel) ----
// Udtrukket fra Folgesvend.tsx (review 27 W-K1) — samme komponent, blot flyttet fil.
import { Suspense, useEffect, useState, type CSSProperties } from 'react';
import { T } from '../theme';
import { Link } from '../Link';
import { personPath } from '../data/nav';
import { initials } from '../data/format';
import { childrenOf, parentsOf } from '../data/model';
import { pickPortrait, withUrl } from '../data/media';
import type { PersonDetailData } from '../data/public';
import type { Model } from '../data/types';
import { erTekniskLinje } from '../data/lineage';
import {
  aegteskabsKilder as aegteskabsKilderFor, boerneKilder as boerneKilderFor, byggUdgaveFakta, byggUdgaveVaelger,
  familieIderForPerson, foraelderKilder as foraelderKilderFor, kildeLinje, lifeJourney, udgaveForRaekker,
  udgaverMedFakta, type BioSourceVersionV2, type FamilieKilde, type UdgaveChip,
} from '@daa/core';
import { fetchFamilySources } from '../data/familySources';
import { NarrativRenderer } from './NarrativRenderer';
import { PersonFakta } from './PersonFakta';
import { Lightbox } from './Lightbox';
import { MediaThumb, BookmarkFlag, Label } from './primitives';
import { ExpandableMiniMap, MapFallback } from './lazyMaps';

export function DetailPanel({ model, focusId, detail, onPick, backName, onBack, onClose, onFocusTree, onRelate, onVisPraesens, isMe, onToggleMe, isBookmarked, onToggleBookmark, geoLoading }: {
  model: Model; focusId: string; detail: PersonDetailData | null; onPick: (id: string) => void;
  backName: string | null; onBack: () => void; onClose?: () => void; onFocusTree: () => void; onRelate: () => void;
  onVisPraesens?: () => void;
  isMe: boolean; onToggleMe: () => void; isBookmarked: boolean; onToggleBookmark: () => void;
  geoLoading: boolean;
}) {
  // Lightbox (Slice A): useState skal stå FØR den betingede return nedenfor (Rules of Hooks) —
  // portræt + galleri bliver ÉT navigerbart sæt (portræt først), så pil-tasterne bladrer gennem
  // alle personens billeder uanset hvilket der blev klikket på.
  const [lightbox, setLightbox] = useState<number | null>(null);
  // Udgavevælger (6e-1, spec §5.5): ÉN chip-liste styrer både biografien og fakta-udgaven. Læserens valg er
  // bundet til personen og chippens identitet (art, udgave, post) — ikke til detalje-objektet, så en genhentning for
  // samme person (fx når geo ankommer) bevarer valget. Findes chippen ikke i de aktuelle data, gælder standarden,
  // uden at valget glemmes; en ny person giver altid standarden. Afledt, ikke nulstillet i en effekt.
  const [valg, setValg] = useState<{ focusId: string; noegle: string } | null>(null);
  const faktaInput = detail?.faktaInput ?? null;
  const udgaver = model.udgaver ?? [];
  const vaelger = byggUdgaveVaelger(detail?.bioVersions ?? [], udgaver, faktaInput ? udgaverMedFakta(faktaInput) : []);
  const valgtFundet = valg && valg.focusId === focusId ? vaelger.chips.findIndex((c) => chipNoegle(c) === valg.noegle) : -1;
  const valgtIdx = valgtFundet >= 0 ? valgtFundet : vaelger.standard;
  const vaelgChip = (idx: number) => {
    const c = vaelger.chips[idx];
    if (c) setValg({ focusId, noegle: chipNoegle(c) });
  };
  const aktivChip: UdgaveChip | null = vaelger.chips[valgtIdx] ?? null;
  // En chip fra en ukendt udgave (fx »label:…« uden udgaveoplysninger) filtrerer intet: alt vises som i dag.
  const valgtUdgave = aktivChip && udgaver.some((u) => u.sourceId === aktivChip.sourceId) ? aktivChip.sourceId : null;
  const faktaVisning = faktaInput ? byggUdgaveFakta(faktaInput, valgtUdgave) : null;
  // Trin 5b 2a (spec §5.2): kilder på ægteskab og forældrelinje. Hentes pr. person; et svar for en
  // tidligere person ignoreres. Fejl giver [] i datalaget, så panelet aldrig brydes. Afhænger af
  // model.indexes, ikke model: et nyt modelobjekt (fx når geo ankommer) skal ikke hente kilderne igen.
  const [familieKilder, setFamilieKilder] = useState<FamilieKilde[]>([]);
  useEffect(() => {
    let aktiv = true;
    setFamilieKilder([]);
    const { aegteskaber, foraeldreFamilier } = familieIderForPerson(model.indexes, focusId);
    const ids = [...aegteskaber.map((a) => a.familyId), ...foraeldreFamilier];
    void fetchFamilySources(ids).then((k) => { if (aktiv) setFamilieKilder(k); });
    return () => { aktiv = false; };
  }, [focusId, model.indexes]);
  const p = model.byId[focusId];
  if (!p) return null;
  const familieIder = familieIderForPerson(model.indexes, focusId);
  // Kildefiltrene bor i core (6d-3 spor L): modparten slås op kanonisk, så en kilde fra en sammenfoldet
  // udgaves post (fx 1939's alias-række) vises hos den kanoniske person.
  const canon = model.canonicalIdById ?? {};
  const aegteskabsKilder = (spouseId: string | null) => aegteskabsKilderFor(familieKilder, familieIder, spouseId, focusId, canon);
  const foraelderKilder = (parentId: string) => foraelderKilderFor(familieKilder, familieIder, parentId, canon);
  const boerneKilder = boerneKilderFor(familieKilder, familieIder, focusId, canon);
  // Samme ægteskab kan være bundet fra flere udgaver/poster; nøglen skal derfor også bære kilden.
  const kildeNøgle = (k: FamilieKilde) => [k.familyId, k.slags, k.counterpartPersonId, k.sourceLabel, k.sourceRecordRef ?? k.recordLabel].join('|');
  const parents = parentsOf(model, focusId);
  const spouses = (model.indexes.spousesBy[focusId] ?? []);
  const children = childrenOf(model, focusId);
  // Tekniske linjenøgler (legacy-source:…, lineage.ts) vises aldrig (spec §5.7) — ellers faldt hovedet tilbage
  // til »Linje <nøgle>«.
  const linjer = (model.lineage?.byPerson[focusId] ?? []).filter((lk) => !erTekniskLinje(lk));
  // Bog-nummeret ("Linje II, nr. 4") vinder; citation-proveniensen udfylder kun for personer bogen
  // ikke gav et opslag — typisk ægtefæller, der ellers stod helt uden kilde.
  const sources = model.sourcesBy?.[focusId]?.length ? model.sourcesBy[focusId] : (detail?.sources ?? []);
  // Portræt = hovedbilledet; galleri = de øvrige medier (materiale). RLS-gatet i data-laget.
  const media = detail?.media ?? [];
  const portrait = pickPortrait(media);
  const gallery = media.filter((m) => m.url && m.id !== portrait?.id);
  const lightboxItems = withUrl([portrait, ...gallery]);
  // Proveniens: er personen foldet af flere DAA-poster (samme_som), vis hvilke linjer/numre.
  const mergedFrom = p.mergedFrom ?? [];
  // Godser (spec §5.8): kun dem, hvis personrække hører til den valgte udgave, eller hvis udgave ikke kendes.
  // Rækkens udgave som for fakta (§5.1): fakta-rækkernes udgave, ellers personrækkens eksterne nøgle.
  const raekkeUdgave = faktaInput ? udgaveForRaekker(faktaInput) : {};
  const godsUdgave = (personId: string): string | null => {
    if (!faktaInput) return null;
    const r = raekkeUdgave[personId];
    if (r !== undefined) return r;
    const ext = faktaInput.udgaveForPersonRaekke[personId];
    return ext != null && udgaver.some((u) => u.sourceId === ext) ? ext : null;
  };
  const godser = (detail?.estates ?? [])
    .filter((e) => { const u = godsUdgave(e.personId); return valgtUdgave == null || u == null || u === valgtUdgave; })
    .filter((e, i, alle) => alle.findIndex((x) => x.id === e.id) === i);
  // »Tidligere udgave« kun når den aktive chips udgave er ældre end standardens (årstal); ukendt år → ingen etiket.
  const standardChip = vaelger.chips[vaelger.standard] ?? null;
  const chipAar = (c: UdgaveChip): number | null => udgaver.find((u) => u.sourceId === c.sourceId)?.aar
    ?? (c.art === 'post' ? (c.version as Partial<BioSourceVersionV2>).sourceYear ?? null : null);
  const aktivAar = aktivChip ? chipAar(aktivChip) : null;
  const standardAar = standardChip ? chipAar(standardChip) : null;
  const tidligereUdgave = aktivAar != null && standardAar != null && aktivAar < standardAar;
  const proveniens =
    mergedFrom.length > 1
      ? mergedFrom
          .map((m) => {
            const navn = m.linje ? model.lineage?.navn[m.linje] ?? `linje ${m.linje}` : 'ukendt linje';
            const ref = m.linje && m.nr != null ? ` (${m.linje}-${m.nr_label ?? m.nr})` : '';
            return `${navn}${ref}`;
          })
          .join(' og ')
      : null;
  return (
    <>
    <div data-scroll style={{ flex: 'none', width: '50%', maxWidth: 760, minWidth: 430, borderLeft: '1px solid rgba(34,31,26,.1)', background: T.paper, overflowY: 'auto' }}>
      <div style={{ padding: '24px 24px 36px' }}>
        {(backName || onClose) && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 14 }}>
            {backName ? (
              <div onClick={onBack} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>‹ Tilbage til {backName}</div>
            ) : <span />}
            {/* Luk detaljen (§5): navigerer til /stamtrae → fuldt-bredt træ, samme centrum. */}
            {onClose && (
              <div onClick={onClose} title="Luk detalje (Esc)" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: T.sans, fontSize: 13, fontWeight: 600, color: T.muted, cursor: 'pointer', padding: '4px 9px', borderRadius: 8, background: T.panel, border: '1px solid rgba(34,31,26,.12)', flex: 'none' }}>
                Luk
                <svg viewBox="0 0 24 24" width={13} height={13} fill="none" stroke={T.muted} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M18 6L6 18M6 6l12 12" /></svg>
              </div>
            )}
          </div>
        )}
        <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
          {portrait ? (
            <div style={{ flex: 'none' }}><MediaThumb m={portrait} w={92} h={116} radius={11} onClick={() => setLightbox(0)} /></div>
          ) : (
            <div style={{ width: 92, height: 116, borderRadius: 11, background: 'repeating-linear-gradient(45deg,#ece4d6 0 9px,#e2d8c8 9px 18px)', border: '1px solid rgba(34,31,26,.1)', flex: 'none', display: 'flex', alignItems: 'flex-end', padding: 8 }}><span style={{ fontFamily: T.mono, fontSize: 10, color: T.muted }}>portræt</span></div>
          )}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <div style={{ fontFamily: T.serif, fontSize: 27, lineHeight: 1, fontWeight: 600, minWidth: 0 }}>{p.name}</div>
              <BookmarkFlag active={isBookmarked} onClick={onToggleBookmark} />
            </div>
            {p.years && <div style={{ fontFamily: T.mono, fontSize: 12, color: T.muted2, marginTop: 6 }}>{p.years}</div>}
            {/* Badges: ★ Dig + Linje(r) + titel. */}
            {(isMe || linjer.length > 0 || p.title) && (
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 9 }}>
                {isMe && <div style={{ fontFamily: T.sans, fontSize: 11.5, fontWeight: 700, color: T.paper, background: T.bordeaux, padding: '4px 9px', borderRadius: 6 }}>★ Dig</div>}
                {linjer.map((lk) => (
                  <div key={lk} style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted, background: T.beige, border: '1px solid rgba(34,31,26,.1)', padding: '4px 8px', borderRadius: 6 }}>{model.lineage?.navn[lk] ?? `Linje ${lk}`}</div>
                ))}
                {p.title && <div style={{ fontSize: 12, fontWeight: 600, color: T.bordeaux, background: '#f4e2e6', border: '1px solid rgba(136,26,51,.16)', padding: '4px 9px', borderRadius: 6 }}>{p.title}</div>}
              </div>
            )}
            {proveniens && (
              <div style={{ fontFamily: T.sans, fontSize: 12, color: T.muted2, marginTop: 8, lineHeight: 1.45 }}>
                Optræder i Aarbogen som {proveniens}.
              </div>
            )}
          </div>
        </div>

        {parents.length > 0 && (
          <div style={{ marginTop: 16, display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '4px 7px' }}>
            <span style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', color: T.gold }}>Barn af</span>
            {parents.map((pa, i) => (
              <span key={pa.id} style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                {i > 0 && <span style={{ fontFamily: T.serif, fontSize: 16, fontStyle: 'italic', color: T.gold }}>&amp;</span>}
                <Link href={personPath(pa.id)} onNavigate={() => onPick(pa.id)} style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, color: T.bordeaux }}>{pa.name} ›</Link>
                {foraelderKilder(pa.id).map((k) => (
                  <KildeLinjeVisning key={kildeNøgle(k)} kilde={k} chips={vaelger.chips} onVaelg={vaelgChip} />
                ))}
              </span>
            ))}
          </div>
        )}

        {/* Udgavevælger + biografi (6e-1, spec §5.5): chips pr. biografipost og pr. udgave med fakta uden
            biografi. Kun én chip → ingen vælger. Ingen biografi i nogen udgave → et lille udgaveskift over fakta. */}
        {vaelger.form !== 'skift' && (() => {
          const bioText = aktivChip
            ? (aktivChip.art === 'post' ? aktivChip.version.narrativeText : '')
            : (detail?.bio ?? '');
          const visChips = vaelger.form === 'chips';
          if (!bioText && !visChips) return null;
          return (
            <div style={{ marginTop: 14 }}>
              {visChips && (
                <UdgaveKnapper chips={vaelger.chips} valgt={valgtIdx} onVaelg={vaelgChip} style={{ marginBottom: 9 }} />
              )}
              {visChips && tidligereUdgave && (
                <div style={{ fontFamily: T.sans, fontSize: 11.5, color: T.muted2, marginBottom: 5 }}>Tidligere udgave</div>
              )}
              {bioText ? (
                <div style={{ fontSize: 15, lineHeight: 1.55, color: '#3d382f' }}>
                  <NarrativRenderer tekst={bioText} onPickPerson={onPick} linkColor={T.bordeaux} inactiveColor={T.muted2} />
                </div>
              ) : (
                <div style={{ fontFamily: T.sans, fontSize: 13, color: T.muted3 }}>Ingen biografi fra denne udgave</div>
              )}
            </div>
          );
        })()}

        {/* Livskort: kun hvis personen har mindst ét geo-punkt (undgår tom-boks-støj for de fleste). */}
        {/* geo er tomt indtil loadGeo() er kaldt (review 27 P3, "lazy geo-kæde") — de FLESTE
            personer ender uden geo-punkter, så vi viser IKKE en midlertidig boks mens den henter
            (ville ellers dukke op og forsvinde igen for langt de fleste — "skal ikke flimre").
            Godser-kort/Slægtens kort er eksplicitte kort-flader med egen "Indlæser kort…"-plads;
            minikortet her er blot spekulativt. */}
        {!geoLoading && model.geo && lifeJourney(model.geo, focusId).length > 0 && (
          <div style={{ marginTop: 14 }}>
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted2, marginBottom: 6 }}>Livsrejse</div>
            <Suspense fallback={<MapFallback />}>
              <ExpandableMiniMap points={lifeJourney(model.geo, focusId)} />
            </Suspense>
          </div>
        )}

        {spouses.length > 0 && (
          <div style={{ marginTop: 14, fontFamily: T.serif, fontSize: 16, fontStyle: 'italic', color: T.muted, lineHeight: 1.5 }}>⚭ gift med{' '}
            {spouses.map((sp, i) => (
              <span key={(sp.id ?? sp.name) + i}>
                {i > 0 && <span style={{ color: T.gold }}>· </span>}
                {sp.id ? <Link href={personPath(sp.id)} onNavigate={() => onPick(sp.id!)} style={{ fontWeight: 600, fontStyle: 'normal', color: T.bordeaux }}>{sp.name} ›</Link> : <span>{sp.name}</span>}
                {aegteskabsKilder(sp.id).map((k) => (
                  <KildeLinjeVisning key={kildeNøgle(k)} kilde={k} chips={vaelger.chips} onVaelg={vaelgChip} />
                ))}
              </span>
            ))}
          </div>
        )}

        {children.length > 0 && (
          <>
            <Label>Børn</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
              {children.map((c) => (
                <Link key={c.id} href={personPath(c.id)} onNavigate={() => onPick(c.id)} style={{ display: 'flex', alignItems: 'center', gap: 8, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 9, padding: '6px 11px 6px 7px' }}>
                  <div style={{ width: 26, height: 26, borderRadius: '50%', background: T.beige, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none', fontFamily: T.serif, fontSize: 12, fontWeight: 600, color: T.bordeaux }}>{initials(c.name)}</div>
                  <span style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600 }}>{c.born != null ? `${c.name.split(' ')[0]} · ${c.born}` : c.name.split(' ')[0]}</span>
                </Link>
              ))}
            </div>
            {boerneKilder.map((k) => (
              <KildeLinjeVisning key={kildeNøgle(k)} kilde={k} chips={vaelger.chips} onVaelg={vaelgChip} />
            ))}
          </>
        )}

        {vaelger.form === 'skift' && (
          <UdgaveKnapper chips={vaelger.chips} valgt={valgtIdx} onVaelg={vaelgChip} style={{ marginTop: 18 }} />
        )}
        {detail && <PersonFakta visning={faktaVisning} error={detail.factsError} />}

        {detail && detail.offices.length > 0 && (
          <>
            <Label>Embeder, rang &amp; hverv</Label>
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {detail.offices.map((o, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'baseline', gap: 10, padding: '7px 0', borderBottom: '1px solid rgba(34,31,26,.07)' }}>
                  <span style={{ flex: 1, fontSize: 14, color: '#3d382f', lineHeight: 1.3 }}>{o.label}</span>
                  {o.period && <span style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted2, flex: 'none', whiteSpace: 'nowrap' }}>{o.period}</span>}
                </div>
              ))}
            </div>
          </>
        )}

        {godser.length > 0 && (
          <>
            <Label>Godser &amp; besiddelser</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
              {godser.map((e) => (
                <span key={e.id} style={{ display: 'inline-flex', alignItems: 'center', gap: 6, background: T.panel, border: '1px solid rgba(34,31,26,.1)', borderRadius: 8, padding: '6px 10px', fontFamily: T.serif, fontSize: 15, fontWeight: 600, color: T.ink }}>⌂ {e.navn}</span>
              ))}
            </div>
          </>
        )}

        {gallery.length > 0 && (
          <>
            <Label>Materiale</Label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {gallery.map((m) => (
                <MediaThumb key={m.id} m={m} w={84} h={84} radius={9}
                  onClick={() => setLightbox(lightboxItems.findIndex((x) => x.id === m.id))} />
              ))}
            </div>
          </>
        )}

        {detail === null && <div style={{ marginTop: 18, fontSize: 13, color: T.muted3 }}>Henter detaljer…</div>}

        {/* Kilde i Aarbogen (§ + trykt værk + "Linje X, nr. N"). */}
        {sources.length > 0 && (
          <>
            <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '22px 0 8px' }}>Kilde i Aarbogen</div>
            {sources.map((s, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '9px 0', borderBottom: '1px solid rgba(34,31,26,.08)' }}>
                <span style={{ fontFamily: T.serif, fontSize: 18, color: T.bordeaux, flex: 'none' }}>§</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: T.sans, fontSize: 14, fontWeight: 600, color: T.ink, lineHeight: 1.25 }}>{s.work}</div>
                  {s.ref && <div style={{ fontFamily: T.mono, fontSize: 11, color: T.muted2, marginTop: 2 }}>{s.ref}</div>}
                </div>
              </div>
            ))}
          </>
        )}

        {/* Handlinger: fokus · slægtskab · "det er mig"-toggle. */}
        <div onClick={onFocusTree} style={{ marginTop: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: '#3d382f', background: T.panel, border: '1.5px solid rgba(34,31,26,.16)', padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>
          <span style={{ fontSize: 14 }}>⊹</span> Sæt i fokus i stamtræet
        </div>
        <div style={{ marginTop: 9, display: 'flex', gap: 9 }}>
          <div onClick={onRelate} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: T.paper, background: T.bordeaux, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>Find slægtskab</div>
          <div onClick={onToggleMe} title={isMe ? 'Fjern din markering' : 'Marker denne person som dig'} style={{ flex: 1, textAlign: 'center', fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, color: isMe ? T.bordeaux : '#3d382f', background: isMe ? '#f8ecef' : T.panel, border: `1.5px solid ${isMe ? T.bordeaux : 'rgba(34,31,26,.16)'}`, padding: '11px 0', borderRadius: 10, cursor: 'pointer' }}>{isMe ? '★ Dette er dig' : 'Det er mig'}</div>
        </div>
        {onVisPraesens && (
          <div onClick={onVisPraesens} style={{ cursor: 'pointer', fontFamily: T.sans, fontSize: 13, color: T.bordeaux, marginTop: 10 }}>
            Vis i præsensliste ↗
          </div>
        )}
      </div>
    </div>
    {lightbox != null && (
      <Lightbox items={lightboxItems} index={lightbox} onClose={() => setLightbox(null)} onNavigate={setLightbox} />
    )}
    </>
  );
}

// En chips identitet på tværs af genhentninger: art, udgave og post (postens ref, ellers etiketten).
function chipNoegle(c: UdgaveChip): string {
  return c.art === 'post' ? `post:${c.sourceId}:${c.version.recordRef ?? c.label}` : `udgave:${c.sourceId}`;
}

// Udgavevælgerens knapper. Etiketten er chippens (core har allerede fjernet tekniske postnøgler).
function UdgaveKnapper({ chips, valgt, onVaelg, style }: {
  chips: UdgaveChip[]; valgt: number; onVaelg: (idx: number) => void; style?: CSSProperties;
}) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, ...style }}>
      {chips.map((c, i) => (
        <button key={`${c.art}:${c.sourceId}:${i}`} type="button" aria-pressed={i === valgt} onClick={() => onVaelg(i)} style={{
          fontFamily: T.mono, fontSize: 10.5, fontWeight: 600, cursor: 'pointer',
          color: i === valgt ? T.paper : T.muted,
          background: i === valgt ? T.bordeaux : T.beige,
          border: '1px solid rgba(34,31,26,.12)', padding: '4px 9px', borderRadius: 6,
        }}>
          {c.label}
        </button>
      ))}
    </div>
  );
}

// Kildelinjen »Kilde: ‹udgave› · ‹post›«. Er posten en af personens egne biografiposter, vælger et klik
// den chip; ellers (fx forælderens post) er linjen ren tekst.
function KildeLinjeVisning({ kilde, chips, onVaelg }: {
  kilde: FamilieKilde; chips: UdgaveChip[]; onVaelg: (idx: number) => void;
}) {
  const idx = kilde.sourceRecordRef
    ? chips.findIndex((c) => c.art === 'post' && c.version.recordRef === kilde.sourceRecordRef) : -1;
  const stil = { display: 'block', fontFamily: T.sans, fontSize: 11.5, fontStyle: 'normal' as const, color: T.muted2 };
  return idx >= 0
    ? <button type="button" onClick={() => onVaelg(idx)} style={{ ...stil, background: 'none', border: 0, padding: 0, cursor: 'pointer', textAlign: 'left' }}>{kildeLinje(kilde)}</button>
    : <span style={stil}>{kildeLinje(kilde)}</span>;
}

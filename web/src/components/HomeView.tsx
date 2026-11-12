// Hovedsiden (webredesign fase 4, tegningen »Hovedside A · Værket«): titel og søgning ·
// slægtsregistret · en lille indgang til »Er vi i familie?« · feedet. Med færre end tre slægter
// står registret kompakt, og feedet bærer siden.
//
// Bevidst udeladt: »Nyt i Aarbogen« (der findes ingen nyhedsdata), slægtsbeskrivelse og våben på
// registerkortet (monogram i stedet; intet opdigtet), filterknapper og sidefod fra tegningen.
// »Redaktionen foreslår« (forsideStartpersoner i data/home.ts) flytter til slægtens forside (fase 5).
import { useEffect, useState } from 'react';
import { T } from '../theme';
import { radius } from '@daa/theme';
import { Link } from '../Link';
import { navigate } from '../router';
import { SLAEGTER, slaegtPath, soegPath } from '../data/nav';
import { FeedStreamView } from './feed/FeedStreamView';
import { fetchFeedPins } from '../data/feedPins';
import type { FeedPinInput } from '@daa/feed';
import type { Model } from '../data/types';
import type { ArmsItem, EstateItem } from '../data/public';

const etiket = { margin: 0, fontFamily: T.mono, fontSize: 11, letterSpacing: '.16em', textTransform: 'uppercase', color: T.goldInk, fontWeight: 400 } as const;

export function HomeView({
  model, personCount, estates, onPickPerson, onBrowseAll, onOpenEstate,
  arms, meId, focusId, bookmarkedIds, bookmarksReady, bookmarkHydrationVersion, bookmarkOwnerId,
  hasBookmark, onSaveBookmark, onOpenArms, onOpenSlaegt,
}: {
  model: Model | null;
  personCount: number;
  estates: EstateItem[] | null;
  onPickPerson: (id: string) => void;
  onBrowseAll: () => void;
  onOpenEstate: (id: string) => void;
  arms: ArmsItem[] | null;
  meId: string | null;
  focusId: string | null;
  bookmarkedIds: string[];
  bookmarksReady: boolean;
  bookmarkHydrationVersion: number;
  bookmarkOwnerId: string | null;
  hasBookmark: (id: string) => boolean;
  onSaveBookmark: (id: string) => void;
  onOpenArms: () => void;
  onOpenSlaegt: (aId: string, bId: string) => void;
}) {
  // Redaktionens fastgjorte kort skal stå først i feedet; feedet monteres derfor først, når
  // pins er hentet (ellers kom de efter første uddeling). fetchFeedPins giver [] ved fejl.
  const [feedPins, setFeedPins] = useState<FeedPinInput[] | null>(null);
  const [q, setQ] = useState('');
  useEffect(() => {
    let alive = true;
    void fetchFeedPins().then((pins) => { if (alive) setFeedPins(pins); }, () => { if (alive) setFeedPins([]); });
    return () => { alive = false; };
  }, []);

  const linjer = model?.lineage?.list.length ?? 0;
  const udgaver = (model?.udgaver ?? []).map((u) => u.label).filter(Boolean);

  return (
    <div style={{ padding: 'clamp(24px, 4vw, 40px) clamp(16px, 4vw, 44px) 54px', maxWidth: 1140, margin: '0 auto' }}>
      <header style={{ maxWidth: 720 }}>
        <p style={etiket}>Danmarks Adels Aarbog</p>
        <h1 style={{ margin: '8px 0 0', fontFamily: T.serif, fontSize: 'clamp(32px, 6vw, 44px)', lineHeight: 1.05, fontWeight: 600, color: T.ink }}>Slå op i Aarbogen</h1>
        <p style={{ margin: '12px 0 0', fontFamily: T.sans, fontSize: 16, lineHeight: 1.5, color: T.inkSecondary }}>
          Find en person i de slægter, Aarbogen har lagt ind, eller begynd i en slægt.
        </p>
        <form role="search" onSubmit={(e) => { e.preventDefault(); navigate(soegPath(q.trim())); }} style={{ display: 'flex', gap: 8, marginTop: 20 }}>
          <label htmlFor="forside-soeg" style={{ position: 'absolute', left: -9999 }}>Søg efter en person</label>
          <input id="forside-soeg" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Søg efter en person"
            style={{ flex: 1, minWidth: 0, fontFamily: T.sans, fontSize: 16, lineHeight: '22px', padding: '12px 15px', borderRadius: radius.field, border: `1px solid ${T.lineStrong}`, background: T.surfaceRaised, color: T.ink }} />
          <button type="submit" style={{ fontFamily: T.sans, fontSize: 15, fontWeight: 600, padding: '12px 20px', borderRadius: radius.field, border: 0, background: T.bordeaux, color: T.onBordeaux, cursor: 'pointer' }}>Søg</button>
        </form>
      </header>

      <section aria-labelledby="forside-register" style={{ marginTop: 36 }}>
        <h2 id="forside-register" style={etiket}>Slægtsregistret</h2>
        <ul style={{ listStyle: 'none', margin: '12px 0 0', padding: 0, display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(min(100%, 320px), 1fr))', gap: 14 }}>
          {SLAEGTER.map((s) => (
            <li key={s.slug}>
              <Link href={slaegtPath(s.slug)} style={{ display: 'flex', gap: 14, alignItems: 'center', padding: '16px 18px', background: T.surfaceRaised, border: `1px solid ${T.line}`, borderRadius: radius.card, textDecoration: 'none', color: T.ink }}>
                <span aria-hidden="true" style={{ flex: 'none', width: 48, height: 48, borderRadius: '50%', border: `1px solid ${T.lineStrong}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 24, color: T.bordeaux }}>{s.navn.slice(0, 1)}</span>
                <span style={{ minWidth: 0 }}>
                  <span style={{ display: 'block', fontFamily: T.serif, fontSize: 22, fontWeight: 600, lineHeight: 1.1 }}>{s.navn}</span>
                  <span style={{ display: 'block', fontFamily: T.sans, fontSize: 13, color: T.inkMuted, marginTop: 4 }}>
                    {[
                      `${personCount} personer`,
                      linjer > 0 ? `${linjer} linjer` : null,
                      udgaver.length > 0 ? `udgaver: ${udgaver.join(', ')}` : null,
                    ].filter(Boolean).join(' · ')}
                  </span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
        <p style={{ margin: '14px 0 0', fontFamily: T.sans, fontSize: 14, color: T.inkSecondary }}>
          Er vi i familie?{' '}
          <Link href="/slaegtskab" style={{ color: T.bordeaux, fontWeight: 600 }}>Find slægtskabet mellem to personer →</Link>
        </p>
      </section>

      <section aria-labelledby="forside-feed" style={{ marginTop: 40 }}>
        <h2 id="forside-feed" style={{ ...etiket, marginBottom: 14 }}>Fra Aarbogen</h2>
        {model && feedPins ? (
          <FeedStreamView
            model={model}
            estates={estates}
            arms={arms}
            meId={meId}
            focusId={focusId}
            feedPins={feedPins}
            bookmarkedIds={bookmarkedIds}
            bookmarksReady={bookmarksReady}
            bookmarkHydrationVersion={bookmarkHydrationVersion}
            bookmarkOwnerId={bookmarkOwnerId}
            hasBookmark={hasBookmark}
            onSaveBookmark={onSaveBookmark}
            onOpenPerson={onPickPerson}
            onOpenEstate={onOpenEstate}
            onOpenArms={onOpenArms}
            onOpenSlaegt={onOpenSlaegt}
            onBrowseAll={onBrowseAll}
          />
        ) : (
          <p role="status" style={{ margin: 0, fontSize: 14, color: T.inkMuted }}>Henter blade fra Aarbogen …</p>
        )}
      </section>
    </div>
  );
}

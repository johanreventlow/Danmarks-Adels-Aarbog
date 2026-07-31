// Fuld "Mine bogmærker"-center-visning (web v3 Slice 1 — spec §3.3). Ren præsentationskomponent:
// al lager-/sorteringslogik bor i data/bookmarks.ts (buildBookmarkList), her kun rendering + wiring.
import { useMemo } from 'react';
import { T } from '../theme';
import { ViewHeader, Avatar, BookmarkFlag } from './primitives';
import { buildBookmarkList, type BookmarkSort } from '../data/bookmarks';
import type { Model } from '../data/types';

export function BookmarksView({ model, ids, sort, setSort, onPick, onRemove, loggedIn, onRequireLogin }: {
  model: Model; ids: string[]; sort: BookmarkSort; setSort: (s: BookmarkSort) => void;
  onPick: (id: string) => void; onRemove: (id: string) => void;
  loggedIn: boolean; onRequireLogin: () => void;
}) {
  // ids er nu en stabil array-reference fra Folgesvend (useMemo på bookmarks.ids) — memoisér
  // også selve grupperingen her, så et re-render der ikke ændrer bogmærker ikke sorterer igen.
  const groups = useMemo(() => buildBookmarkList(ids, model, sort), [ids, model, sort]);
  const total = groups.reduce((n, g) => n + g.people.length, 0);

  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <ViewHeader title="Mine bogmærker" />
          <div style={{ fontFamily: T.mono, fontSize: 11.5, color: T.muted2, marginTop: -4 }}>{total} {total === 1 ? 'bogmærke' : 'bogmærker'}</div>
        </div>
        <div style={{ display: 'flex', background: T.beige, borderRadius: 10, padding: 3, gap: 3, flex: 'none' }}>
          {([['linje', 'Linje'], ['navn', 'A–Å']] as const).map(([key, label]) => {
            const active = sort === key;
            return (
              <div key={key} onClick={() => setSort(key)} style={{ padding: '7px 16px', borderRadius: 7, fontFamily: T.sans, fontSize: 13.5, fontWeight: 600, cursor: 'pointer', background: active ? T.paper : 'transparent', color: active ? T.bordeaux : '#8a8170' }}>{label}</div>
            );
          })}
        </div>
      </div>

      {total === 0 ? (
        <div style={{ border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 20, background: T.paper, fontSize: 14, color: T.muted3, textAlign: 'center' }}>
          {loggedIn ? (
            'Ingen bogmærker endnu — tryk flaget på en person for at gemme den her.'
          ) : (
            <>
              Log ind for at samle dine bogmærker på tværs af dine enheder.
              <div onClick={onRequireLogin} style={{ marginTop: 10, display: 'inline-block', fontWeight: 600, color: T.bordeaux, cursor: 'pointer' }}>Log ind ›</div>
            </>
          )}
        </div>
      ) : (
        groups.map((g) => (
          <div key={g.linje ?? 'flat'} style={{ marginBottom: 20 }}>
            {g.linje != null && (
              <div style={{ fontFamily: T.mono, fontSize: 10, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 10px' }}>{g.navn}</div>
            )}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {g.people.map((p) => (
                <div key={p.id} onClick={() => onPick(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 12px', borderRadius: 10, background: T.paper, border: '1px solid rgba(34,31,26,.1)', cursor: 'pointer' }}>
                  <Avatar n={p.name} size={32} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: T.serif, fontSize: 17, fontWeight: 600, lineHeight: 1.05 }}>{p.name}</div>
                    {p.years && <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 1 }}>{p.years}</div>}
                  </div>
                  <BookmarkFlag active onClick={() => onRemove(p.id)} />
                </div>
              ))}
            </div>
          </div>
        ))
      )}
    </div>
  );
}

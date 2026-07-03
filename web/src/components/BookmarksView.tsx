// Fuld "Mine bogmærker"-center-visning (web v3 Slice 1 — spec §3.3). Ren præsentationskomponent:
// al lager-/sorteringslogik bor i data/bookmarks.ts (buildBookmarkList), her kun rendering + wiring.
import { T } from '../theme';
import { initials } from '../data/format';
import { buildBookmarkList, type BookmarkSort } from '../data/bookmarks';
import type { Model } from '../data/types';

export function BookmarksView({ model, ids, sort, setSort, onPick, onRemove }: {
  model: Model; ids: string[]; sort: BookmarkSort; setSort: (s: BookmarkSort) => void;
  onPick: (id: string) => void; onRemove: (id: string) => void;
}) {
  const groups = buildBookmarkList(ids, model, sort);
  const total = groups.reduce((n, g) => n + g.people.length, 0);

  return (
    <div style={{ padding: '30px 40px 50px', maxWidth: 640 }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 18 }}>
        <div>
          <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.2em', textTransform: 'uppercase', color: T.gold, marginBottom: 6 }}>Slægten Reventlow</div>
          <div style={{ fontFamily: T.serif, fontSize: 30, fontWeight: 600, lineHeight: 1 }}>Mine bogmærker</div>
          <div style={{ fontFamily: T.mono, fontSize: 10.5, color: T.muted2, marginTop: 8 }}>{total} {total === 1 ? 'bogmærke' : 'bogmærker'}</div>
        </div>
        <div style={{ display: 'flex', background: T.beige, borderRadius: 10, padding: 3, gap: 3, flex: 'none' }}>
          {([['linje', 'Linje'], ['navn', 'A–Å']] as const).map(([key, label]) => {
            const active = sort === key;
            return (
              <div key={key} onClick={() => setSort(key)} style={{ padding: '7px 16px', borderRadius: 7, fontFamily: T.sans, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', background: active ? T.paper : 'transparent', color: active ? T.bordeaux : '#8a8170' }}>{label}</div>
            );
          })}
        </div>
      </div>

      {total === 0 ? (
        <div style={{ border: '1px dashed rgba(34,31,26,.2)', borderRadius: 11, padding: 20, background: T.paper, fontSize: 13, color: T.muted3, textAlign: 'center' }}>
          Ingen bogmærker endnu — tryk flaget på en person for at gemme den her.
        </div>
      ) : (
        groups.map((g) => (
          <div key={g.linje ?? 'flat'} style={{ marginBottom: 20 }}>
            {g.linje != null && (
              <div style={{ fontFamily: T.mono, fontSize: 9, letterSpacing: '.14em', textTransform: 'uppercase', color: T.muted3, margin: '6px 0 10px' }}>{g.navn}</div>
            )}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {g.people.map((p) => (
                <div key={p.id} onClick={() => onPick(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '9px 12px', borderRadius: 10, background: T.paper, border: '1px solid rgba(34,31,26,.1)', cursor: 'pointer' }}>
                  <span style={{ width: 32, height: 32, borderRadius: '50%', background: T.beige, border: '1px solid rgba(34,31,26,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: T.serif, fontSize: 13, fontWeight: 600, color: T.bordeaux, flex: 'none' }}>{initials(p.name)}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: T.serif, fontSize: 16, fontWeight: 600, lineHeight: 1.05 }}>{p.name}</div>
                    {p.years && <div style={{ fontFamily: T.mono, fontSize: 9, color: T.muted2, marginTop: 1 }}>{p.years}</div>}
                  </div>
                  <span
                    onClick={(e) => { e.stopPropagation(); onRemove(p.id); }}
                    title="Fjern bogmærke"
                    style={{ fontSize: 14, color: T.muted2, cursor: 'pointer', padding: 4, flex: 'none' }}
                  >
                    ✕
                  </span>
                </div>
              ))}
            </div>
          </div>
        ))
      )}
    </div>
  );
}

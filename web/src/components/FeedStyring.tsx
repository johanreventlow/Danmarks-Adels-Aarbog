import { useEffect, useMemo, useState } from 'react';
import type { FeedPinRow } from '@daa/feed';
import { fetchFeedPinRows } from '../data/feedPins';
import { fetchPubliceredeStories, type StoryPost } from '../data/redaktionRead';
import type { Model } from '../data/types';
import type { Change } from '../data/redaktionWrite';
import { T } from '../theme';

export function bygKortNoegle(slags: 'portrait' | 'story' | 'arkiv', id: string | number): string {
  return `${slags}:${id}`;
}

export function pinStatus(noegle: string, personIds: ReadonlySet<string>, storyIds: ReadonlySet<string>): 'ok' | 'dinglende' | 'ukendt' {
  if (noegle.startsWith('portrait:')) return personIds.has(noegle.slice(9)) ? 'ok' : 'dinglende';
  if (noegle.startsWith('story:')) return storyIds.has(noegle.slice(6)) ? 'ok' : 'dinglende';
  return 'ukendt';
}

type PublicStory = StoryPost & { subjektId: number };

export function FeedStyring({ role, model, run }: {
  role?: string;
  model: Model | null;
  run: (change: Change, titel: string) => Promise<unknown>;
}) {
  const [pins, setPins] = useState<FeedPinRow[]>([]);
  const [stories, setStories] = useState<PublicStory[]>([]);
  const [error, setError] = useState('');
  const [refresh, setRefresh] = useState(0);
  const [query, setQuery] = useState('');
  const [personId, setPersonId] = useState('');
  const [storyId, setStoryId] = useState('');
  const [handling, setHandling] = useState<'pin' | 'skjul'>('pin');

  useEffect(() => {
    let alive = true;
    setError('');
    Promise.all([fetchFeedPinRows(), fetchPubliceredeStories()])
      .then(([p, s]) => { if (alive) { setPins(p); setStories(s); } })
      .catch((e) => alive && setError(String((e as Error)?.message ?? e)));
    return () => { alive = false; };
  }, [refresh]);

  const personIds = useMemo(() => new Set(Object.keys(model?.byId ?? {})), [model]);
  const storyIds = useMemo(() => new Set(stories.map((s) => String(s.id))), [stories]);
  const people = useMemo(() => {
    const q = query.trim().toLocaleLowerCase('da');
    return Object.values(model?.byId ?? {}).filter((p) => !q || p.name.toLocaleLowerCase('da').includes(q)).slice(0, 25);
  }, [model, query]);
  const act = async (change: Change, title: string) => { await run(change, title); setRefresh((x) => x + 1); };
  const box = { background: T.paper, border: '1px solid rgba(34,31,26,.1)', borderRadius: 11, padding: 14 } as const;
  const pill = (active: boolean) => ({ border: 0, borderRadius: 6, padding: '5px 8px', cursor: 'pointer',
    background: active ? T.bordeaux : T.beige, color: active ? T.paper : T.muted, fontFamily: T.mono, fontSize: 10 } as const);

  return <div style={{ maxWidth: 1080, margin: '0 auto', padding: '24px 28px 60px', color: T.ink }}>
    <h1 style={{ fontFamily: T.serif, fontSize: 29, margin: 0 }}>Feed-styring</h1>
    <div style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2, marginTop: 3 }}>
      {role === 'redaktion' ? 'Direkte redaktion' : 'Handlinger sendes som forslag'} · kurerende lag
    </div>
    {error && <div style={{ ...box, marginTop: 14, color: T.bordeaux }}>{error}</div>}

    <h2 style={{ fontFamily: T.serif, marginTop: 24 }}>Pins og skjul</h2>
    <div style={{ display: 'grid', gap: 7 }}>
      {pins.map((pin) => {
        const status = pinStatus(pin.kort_noegle, personIds, storyIds);
        return <div key={pin.kort_noegle} style={{ ...box, display: 'flex', alignItems: 'center', gap: 10 }}>
          <code style={{ fontFamily: T.mono, fontSize: 12 }}>{pin.kort_noegle}</code>
          <span style={{ ...pill(pin.handling === 'pin'), cursor: 'default' }}>{pin.handling}</span>
          <span style={{ fontFamily: T.mono, fontSize: 10, color: T.muted2 }}>{pin.oprettet_naar ?? 'tid ukendt'}</span>
          {status !== 'ok' && <span style={{ fontFamily: T.mono, fontSize: 10, color: status === 'dinglende' ? T.bordeaux : T.muted2 }}>{status}</span>}
          <span style={{ flex: 1 }} />
          <button onClick={() => act({ art: 'fjernFeedPin', subjektType: 'feed_pin', subjektId: '', kortNoegle: pin.kort_noegle }, 'Fjern kurering')} style={pill(false)}>Fjern</button>
        </div>;
      })}
      {!pins.length && <div style={{ color: T.muted2 }}>Ingen kureringer.</div>}
    </div>

    <h2 style={{ fontFamily: T.serif, marginTop: 24 }}>Publicerede stories</h2>
    <div style={{ display: 'grid', gap: 7 }}>
      {stories.map((story) => <div key={story.id} style={box}>
        <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
          <strong style={{ fontFamily: T.serif, fontSize: 17 }}>{story.titel || 'Historie uden titel'}</strong>
          <span style={{ color: T.muted, fontSize: 12 }}>{model?.byId[String(story.subjektId)]?.name ?? `Person #${story.subjektId}`}</span>
          <span style={{ flex: 1 }} />
          <button style={pill(false)} onClick={() => act({ art: 'setStoryStatus', subjektType: 'person', subjektId: String(story.subjektId), storyId: story.id, storyStatus: 'klar' }, 'Afpublicér historie')}>Afpublicér</button>
        </div>
        <div style={{ color: T.muted, fontSize: 13.5, marginTop: 4 }}>{story.tekst.slice(0, 180)}{story.tekst.length > 180 ? '…' : ''}</div>
        <div style={{ fontFamily: T.mono, color: T.muted2, fontSize: 9.5, marginTop: 5 }}>{story.publiceretDato ?? 'publiceringsdato ukendt'}</div>
      </div>)}
      {!stories.length && <div style={{ color: T.muted2 }}>Ingen publicerede stories.</div>}
    </div>

    <h2 style={{ fontFamily: T.serif, marginTop: 24 }}>Pin eller skjul et kort</h2>
    <div style={box}>
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Søg person"
        style={{ width: '100%', padding: 9, border: '1px solid rgba(34,31,26,.15)', borderRadius: 7, background: T.panel }} />
      <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginTop: 8 }}>
        {people.map((p) => <button key={p.id} onClick={() => { setPersonId(p.id); setStoryId(''); }} style={pill(personId === p.id)}>{p.name}</button>)}
      </div>
      <div style={{ fontFamily: T.mono, fontSize: 10, color: T.gold, marginTop: 13 }}>ELLER STORY</div>
      <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginTop: 6 }}>
        {stories.map((s) => <button key={s.id} onClick={() => { setStoryId(String(s.id)); setPersonId(''); }} style={pill(storyId === String(s.id))}>{s.titel || `Story #${s.id}`}</button>)}
      </div>
      <div style={{ display: 'flex', gap: 7, marginTop: 14 }}>
        {(['pin', 'skjul'] as const).map((h) => <button key={h} onClick={() => setHandling(h)} style={pill(handling === h)}>{h}</button>)}
        <button disabled={!personId && !storyId} style={{ ...pill(true), opacity: personId || storyId ? 1 : .45 }}
          onClick={() => {
            const noegle = personId ? bygKortNoegle('portrait', personId) : bygKortNoegle('story', storyId);
            act({ art: 'setFeedPin', subjektType: 'feed_pin', subjektId: '', kortNoegle: noegle, handling }, 'Kurér feed');
          }}>Gem kurering</button>
      </div>
    </div>
  </div>;
}

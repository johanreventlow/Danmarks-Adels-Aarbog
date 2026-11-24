// @vitest-environment jsdom
// »På denne dag«/»I denne måned«: kortet viser den fulde dato stort og kun »Født«/»Død« under, så året ikke står to
// gange (projektejeren 2026-11-24). Kortet findes kun for dag-præcise datoer.
import { render, screen } from '@testing-library/react';
import type { FeedCard } from '@daa/feed';
import { describe, expect, it, vi } from 'vitest';

vi.mock('../../../router', () => ({ navigate: vi.fn() }));
const { PersonFeedCardView } = await import('../PersonFeedCardView');

type Kort = Extract<FeedCard, { kind: 'paadennedag' }>;
const kort = (o: Partial<Kort> = {}): Kort => ({
  kind: 'paadennedag', id: 'paadennedag:a:død:1943', personId: 'a', name: 'Ernst Reventlow', years: '* 1869 † 1943',
  aarstal: 1943, dato: '1943-11-26', hvad: 'død', praecision: 'maaned', kicker: 'I denne måned', ...o,
});
const vis = (k: Kort) => render(<PersonFeedCardView card={k} person={{ name: k.name, years: k.years }} media={[]}
  onOpen={vi.fn()} onSave={vi.fn()} bookmarked={false} />);

describe('PersonFeedCardView — dato-kort', () => {
  it('fuld dato stort, kun »Død« under; året står ikke dobbelt', () => {
    vis(kort());
    expect(screen.getByText('26. nov. 1943')).toBeTruthy();
    expect(screen.getByText('Død')).toBeTruthy();
    expect(screen.queryByText('Død 1943')).toBeNull();
    expect(screen.queryByText('1943')).toBeNull();
  });

  it('født-kort siger »Født«', () => {
    vis(kort({ hvad: 'født', dato: '1936-11-22', aarstal: 1936 }));
    expect(screen.getByText('22. nov. 1936')).toBeTruthy();
    expect(screen.getByText('Født')).toBeTruthy();
  });

  it('hændelses-kort: fuld dato over klausulen', () => {
    vis(kort({ hvad: 'hændelse', dato: '1723-11-18', aarstal: 1723, klausul: 'Blev gehejmeråd.' }));
    expect(screen.getByText('18. nov. 1723')).toBeTruthy();
    expect(screen.getByText('Blev gehejmeråd.')).toBeTruthy();
  });
});

// @vitest-environment jsdom
// Våbensiden med bogens våbengalleri (spec 2026-11-24-billeder-2018-20-design.md, runde 3).
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ArmsView } from '../ArmsView';
import type { MediaItem } from '../../data/media';

const billede = (id: string, titel: string): MediaItem => ({
  id, slags: 'våben', titel, kunstner: '', datering: '', url: `https://x/${id}.jpg`, thumbUrl: `https://x/${id}-t.jpg`,
} as unknown as MediaItem);

describe('ArmsView — våbengalleri', () => {
  it('viser bogens våben med titel', () => {
    render(<ArmsView arms={[]} galleri={[billede('185', 'Våben: von Reventlow'), billede('190', 'Grevskabet Vallø')]} />);
    expect(screen.getByText('Våben i Danmarks Adels Aarbog 2018-20')).toBeTruthy();
    expect(screen.getByText('Våben: von Reventlow')).toBeTruthy();
    expect(screen.getByText('Grevskabet Vallø')).toBeTruthy();
  });

  it('intet galleri (tomt eller ikke hentet) viser intet afsnit', () => {
    const { rerender } = render(<ArmsView arms={[]} galleri={[]} />);
    expect(screen.queryByText('Våben i Danmarks Adels Aarbog 2018-20')).toBeNull();
    rerender(<ArmsView arms={[]} galleri={null} />);
    expect(screen.queryByText('Våben i Danmarks Adels Aarbog 2018-20')).toBeNull();
  });
});

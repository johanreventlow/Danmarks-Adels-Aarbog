// @vitest-environment jsdom
import { render, screen, fireEvent } from '@testing-library/react';
import { MapLightbox, ExpandableMiniMap } from '../MapLightbox';
import type { GeoPoint } from '../../data/types';

const POINTS: GeoPoint[] = [
  { placeId: 'p1', navn: 'Reventlow', lat: 55.5, lon: 10, kind: 'fødsel', personId: 'per1', estateId: null, unionId: null, year: 1700 },
];

describe('MapLightbox', () => {
  it('renderer det forstørrede kort + backdrop', () => {
    render(<MapLightbox points={POINTS} onClose={vi.fn()} />);
    expect(screen.getByTestId('map-lightbox-backdrop')).toBeTruthy();
    expect(screen.getByTestId('map-lightbox-content')).toBeTruthy();
  });

  it('backdrop-klik lukker', () => {
    const onClose = vi.fn();
    render(<MapLightbox points={POINTS} onClose={onClose} />);
    fireEvent.click(screen.getByTestId('map-lightbox-backdrop'));
    expect(onClose).toHaveBeenCalled();
  });

  it('Escape lukker', () => {
    const onClose = vi.fn();
    render(<MapLightbox points={POINTS} onClose={onClose} />);
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalled();
  });

  it('klik på kort-container lukker IKKE (stopPropagation)', () => {
    const onClose = vi.fn();
    render(<MapLightbox points={POINTS} onClose={onClose} />);
    fireEvent.click(screen.getByTestId('map-lightbox-content'));
    expect(onClose).not.toHaveBeenCalled();
  });

  it('×-knap lukker', () => {
    const onClose = vi.fn();
    render(<MapLightbox points={POINTS} onClose={onClose} />);
    fireEvent.click(screen.getByTitle('Luk (Esc)'));
    expect(onClose).toHaveBeenCalled();
  });
});

describe('ExpandableMiniMap', () => {
  it('viser mini-kort uden overlay før klik', () => {
    render(<ExpandableMiniMap points={POINTS} />);
    expect(screen.getByTestId('minimap-expand-trigger')).toBeTruthy();
    expect(screen.queryByTestId('map-lightbox-backdrop')).toBeNull();
  });

  it('klik på mini-kort åbner lightboxen', () => {
    render(<ExpandableMiniMap points={POINTS} />);
    fireEvent.click(screen.getByTestId('minimap-expand-trigger'));
    expect(screen.getByTestId('map-lightbox-backdrop')).toBeTruthy();
  });

  it('Escape lukker den åbnede lightbox igen', () => {
    render(<ExpandableMiniMap points={POINTS} />);
    fireEvent.click(screen.getByTestId('minimap-expand-trigger'));
    expect(screen.getByTestId('map-lightbox-backdrop')).toBeTruthy();
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByTestId('map-lightbox-backdrop')).toBeNull();
  });
});

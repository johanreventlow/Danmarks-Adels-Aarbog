// @vitest-environment jsdom
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from '../ErrorBoundary';

function Boom(): never {
  throw new Error('kaboom');
}

describe('ErrorBoundary', () => {
  it('renderer børn normalt når intet fejler', () => {
    render(<ErrorBoundary><div>hej</div></ErrorBoundary>);
    expect(screen.getByText('hej')).toBeTruthy();
  });

  it('viser fallback-UI når et barn kaster', () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    render(<ErrorBoundary><Boom /></ErrorBoundary>);
    expect(screen.getByText('Noget gik galt.')).toBeTruthy();
    expect(screen.getByText('Genindlæs siden')).toBeTruthy();
    spy.mockRestore();
  });
});

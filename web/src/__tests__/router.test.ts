// @vitest-environment jsdom
import { renderHook, act } from '@testing-library/react';
import { navigate, usePath } from '../router';

describe('router', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/');
  });

  it('navigate() push opdaterer location.pathname og tilføjer en historik-post', () => {
    const before = window.history.length;
    navigate('/person/1');
    expect(window.location.pathname).toBe('/person/1');
    expect(window.history.length).toBe(before + 1);
  });

  it('navigate() replace opdaterer location.pathname UDEN at tilføje en historik-post', () => {
    navigate('/person/1');
    const before = window.history.length;
    navigate('/person/2', { replace: true });
    expect(window.location.pathname).toBe('/person/2');
    expect(window.history.length).toBe(before);
  });

  it('usePath() afspejler den aktuelle path ved mount', () => {
    navigate('/estate/9', { replace: true });
    const { result } = renderHook(() => usePath());
    expect(result.current).toBe('/estate/9');
  });

  it('usePath() opdaterer når navigate() kaldes (push og replace)', () => {
    const { result } = renderHook(() => usePath());
    act(() => navigate('/person/42'));
    expect(result.current).toBe('/person/42');
    act(() => navigate('/person/43', { replace: true }));
    expect(result.current).toBe('/person/43');
  });

  it('usePath() opdaterer ved en popstate-hændelse (browserens back/forward)', () => {
    navigate('/a');
    navigate('/b');
    const { result } = renderHook(() => usePath());
    expect(result.current).toBe('/b');
    act(() => {
      // Simulerer at browseren allerede har rullet URL'en tilbage og fyret popstate —
      // vi tester her KUN vores egen lytter-logik, ikke jsdoms interne back()-timing.
      window.history.replaceState(null, '', '/a');
      window.dispatchEvent(new PopStateEvent('popstate'));
    });
    expect(result.current).toBe('/a');
  });

  it('rydder sin popstate-lytter ved unmount (ingen fejl/advarsel ved efterfølgende navigation)', () => {
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { unmount } = renderHook(() => usePath());
    unmount();
    expect(() => {
      navigate('/efter-unmount');
      window.dispatchEvent(new PopStateEvent('popstate'));
    }).not.toThrow();
    expect(errSpy).not.toHaveBeenCalled();
    errSpy.mockRestore();
  });
});

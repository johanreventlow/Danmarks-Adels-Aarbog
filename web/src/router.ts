// Minimal path-baseret router — ingen ekstern dependency. navigate() opdaterer History API'et
// og notificerer synkront (pushState/replaceState fyrer IKKE selv popstate/hashchange); browserens
// egen back/forward udløser 'popstate', som vi lytter på her og videreformidler til usePath().
import { useEffect, useState } from 'react';

const listeners = new Set<() => void>();
function notify() {
  listeners.forEach((l) => l());
}
if (typeof window !== 'undefined') window.addEventListener('popstate', notify);

export function navigate(path: string, opts: { replace?: boolean; state?: unknown } = {}) {
  const state = opts.state ?? null;
  if (opts.replace) window.history.replaceState(state, '', path);
  else window.history.pushState(state, '', path);
  notify();
}

export function usePath(): string {
  const [path, setPath] = useState(() => window.location.pathname);
  useEffect(() => {
    const onChange = () => setPath(window.location.pathname);
    listeners.add(onChange);
    return () => {
      listeners.delete(onChange);
    };
  }, []);
  return path;
}

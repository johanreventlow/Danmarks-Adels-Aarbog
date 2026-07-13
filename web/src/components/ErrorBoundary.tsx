// review 27 R3: mangler helt — uden en ErrorBoundary giver en render-crash en hvid, tavs
// skærm. Fanger crashes i renderet træ (Folgesvend OG Redaktion) og viser en redaktionelt
// stilet fallback i stedet, med en genindlæs-knap som eneste vej ud (svarer til app'ens
// hard-reload-recovery andre steder, fx før R2's "Prøv igen").
import { Component, type ErrorInfo, type ReactNode } from 'react';
import { T } from '../theme';

type Props = { children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[errorboundary]', error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div style={{ minHeight: '100vh', background: T.pageBg, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, fontFamily: T.sans }}>
        <div style={{ maxWidth: 420, background: T.paper, borderRadius: 16, border: `1px solid ${T.cream}`, padding: '32px 28px', textAlign: 'center' }}>
          <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.bordeaux, marginBottom: 12 }}>Noget gik galt.</div>
          <div style={{ color: T.muted, fontSize: 13, marginBottom: 20 }}>
            Siden stødte på en uventet fejl. Prøv at genindlæse.
          </div>
          <button
            onClick={() => window.location.reload()}
            style={{ background: T.bordeaux, color: T.paper, border: 'none', borderRadius: 10, padding: '10px 22px', fontFamily: T.sans, fontSize: 14, fontWeight: 600, cursor: 'pointer' }}
          >
            Genindlæs siden
          </button>
          <details style={{ marginTop: 18, textAlign: 'left', fontSize: 12, color: T.muted2 }}>
            <summary style={{ cursor: 'pointer' }}>Fejldetaljer</summary>
            <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>{this.state.error.message}</pre>
          </details>
        </div>
      </div>
    );
  }
}

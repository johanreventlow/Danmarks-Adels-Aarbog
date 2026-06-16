import { useEffect, useState } from "react";
import { getRelations, getPersonDetail, resolvePersonId, type PersonDetail, type RelPerson, type Relations } from "./relations";

// Start-fokus: Johan Martin (linje V, nr 186).
const START = { linje: "V", nr: 186 };

export default function App() {
  const [focusId, setFocusId] = useState<number | null>(null);
  const [data, setData] = useState<Relations | null>(null);
  const [detail, setDetail] = useState<PersonDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // resolve startperson én gang
  useEffect(() => {
    resolvePersonId(START.linje, START.nr).then(setFocusId).catch((e) => {
      setError(describe(e));
      setLoading(false);
    });
  }, []);

  useEffect(() => {
    if (focusId == null) return;
    let alive = true;
    setLoading(true);
    Promise.all([getRelations(focusId), getPersonDetail(focusId)])
      .then(([rel, det]) => alive && (setData(rel), setDetail(det), setError(null)))
      .catch((e) => alive && setError(describe(e)))
      .finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [focusId]);

  return (
    <main style={s.page}>
      <header style={s.header}>
        <h1 style={s.h1}>DAA-følgesvend · slægtskab</h1>
        <p style={s.sub}>
          Reventlow PoC · klik en person for at flytte fokus
          {data && focusId !== startEquals(data) && (
            <button style={s.reset} onClick={() => resolvePersonId(START.linje, START.nr).then(setFocusId)}>
              ↩ tilbage til Johan Martin
            </button>
          )}
        </p>
      </header>

      {loading && <p style={s.muted}>Henter…</p>}
      {error && <pre style={s.err}>{error}</pre>}

      {data && !loading && (
        <>
          <FocusCard p={data.person} detail={detail} />
          <Group title="Forældre" people={data.parents} onPick={setFocusId} />
          <Group title="Ægtefælle(r)" people={data.spouses} onPick={setFocusId} />
          <Group title="Søskende" people={data.siblings} onPick={setFocusId} />
          <Group title="Børn" people={data.children} onPick={setFocusId} />
          {emptyAll(data) && <p style={s.muted}>Ingen registrerede nære relationer.</p>}
        </>
      )}
    </main>
  );
}

function FocusCard({ p, detail }: { p: RelPerson; detail: PersonDetail | null }) {
  const facts = (detail?.facts ?? []).filter((f) => f.value);
  return (
    <section style={s.focus}>
      <div style={s.focusName}>{displayName(p)}</div>
      <div style={s.focusMeta}>
        {[p.koen, lifespan(p), extid(p)].filter(Boolean).join(" · ") || "—"}
      </div>
      {facts.length > 0 && (
        <dl style={s.facts}>
          {facts.map((f, i) => (
            <div key={i} style={s.factRow}>
              <dt style={s.factType}>{f.faktatype}</dt>
              <dd style={s.factVal}>{f.value}</dd>
            </div>
          ))}
        </dl>
      )}
      {detail?.narrative && (
        <details style={s.narr}>
          <summary style={s.narrSum}>Fuld biografi (kilde-prosa)</summary>
          <p style={s.narrText}>{detail.narrative}</p>
        </details>
      )}
    </section>
  );
}

function Group({ title, people, onPick }: { title: string; people: RelPerson[]; onPick: (id: number) => void }) {
  if (!people.length) return null;
  return (
    <section style={s.group}>
      <h2 style={s.groupTitle}>{title} <span style={s.count}>{people.length}</span></h2>
      <div style={s.cards}>
        {people.map((p) => (
          <button key={p.id} style={s.card} onClick={() => onPick(p.id)}>
            <div style={s.cardName}>{displayName(p)}</div>
            <div style={s.cardMeta}>{[lifespan(p), extid(p)].filter(Boolean).join(" · ")}</div>
            {p.konfidens && p.konfidens !== "sikker" && (
              <div style={s.konf}>⚠ {p.konfidens}</div>
            )}
          </button>
        ))}
      </div>
    </section>
  );
}

// --- helpers ---
function displayName(p: RelPerson): string {
  const navn = p.visning_navn ?? "(uden navn)";
  const titel = p.visning_titel?.trim();
  if (!titel) return navn;
  // nogle navne har titlen bagt ind (udtræks-inkonsistens) — undgå dobbelt titel
  return navn.toLowerCase().startsWith(titel.toLowerCase()) ? navn : `${titel} ${navn}`;
}
function lifespan(p: RelPerson): string {
  const f = clean(p.visning_foedt), d = clean(p.visning_doed);
  if (f && d) return `${f} – ${d}`;
  if (f) return `* ${f}`;
  if (d) return `${d}`;
  return "";
}
function clean(x: string | null): string {
  return (x ?? "").replace(/^[*†]\s*/, "").trim();
}
function extid(p: RelPerson): string {
  return p.linje && p.nr != null ? `${p.linje}-${p.nr}` : "";
}
function emptyAll(d: Relations): boolean {
  return !d.parents.length && !d.siblings.length && !d.spouses.length && !d.children.length;
}
function startEquals(_d: Relations): number {
  return -1; // altid vis reset-knap (billigt); fokus-id sammenlignes ikke her
}
function describe(e: unknown): string {
  const m = e instanceof Error ? e.message : e && typeof e === "object" ? JSON.stringify(e) : String(e);
  return /permission|row-level|JWT|relation|PGRST|policy/i.test(m)
    ? m + "\n\nMangler måske anon-læseadgang — kør web/dev-rls.sql i Supabase."
    : m;
}

const s: Record<string, React.CSSProperties> = {
  page: { fontFamily: "system-ui, -apple-system, Segoe UI, Roboto, sans-serif", maxWidth: 820, margin: "0 auto", padding: "2rem 1rem", color: "#1a1a1a" },
  header: { marginBottom: "1.25rem" },
  h1: { margin: 0, fontSize: "1.5rem" },
  sub: { margin: "0.25rem 0 0", color: "#666", fontSize: "0.9rem", display: "flex", gap: "0.75rem", alignItems: "center", flexWrap: "wrap" },
  reset: { fontSize: "0.8rem", border: "1px solid #ccc", background: "#fff", borderRadius: 6, padding: "0.15rem 0.5rem", cursor: "pointer" },
  muted: { color: "#999" },
  err: { whiteSpace: "pre-wrap", fontSize: "0.85rem", background: "#fcf3f3", border: "1px solid #e0b4b4", borderRadius: 8, padding: "0.75rem" },
  focus: { border: "2px solid #1a1a1a", borderRadius: 12, padding: "1rem 1.25rem", marginBottom: "1.5rem", background: "#fff" },
  focusName: { fontSize: "1.3rem", fontWeight: 700 },
  focusMeta: { color: "#555", marginTop: "0.25rem", fontSize: "0.9rem" },
  facts: { margin: "0.75rem 0 0", display: "grid", gridTemplateColumns: "auto 1fr", gap: "0.2rem 0.8rem" },
  factRow: { display: "contents" },
  factType: { fontSize: "0.78rem", textTransform: "uppercase", letterSpacing: "0.03em", color: "#8a8a8a" },
  factVal: { margin: 0, fontSize: "0.88rem" },
  narr: { marginTop: "0.8rem", borderTop: "1px solid #eee", paddingTop: "0.5rem" },
  narrSum: { fontSize: "0.82rem", color: "#5a5a5a", cursor: "pointer", fontWeight: 600 },
  narrText: { fontSize: "0.85rem", lineHeight: 1.5, color: "#333", marginTop: "0.5rem", whiteSpace: "pre-wrap" },
  group: { marginBottom: "1.25rem" },
  groupTitle: { fontSize: "0.8rem", textTransform: "uppercase", letterSpacing: "0.05em", color: "#7a7a7a", margin: "0 0 0.5rem" },
  count: { color: "#bbb" },
  cards: { display: "flex", flexWrap: "wrap", gap: "0.6rem" },
  card: { textAlign: "left", border: "1px solid #e2e2e2", borderRadius: 10, padding: "0.6rem 0.8rem", background: "#fff", cursor: "pointer", minWidth: 180, boxShadow: "0 1px 2px rgba(0,0,0,0.04)" },
  cardName: { fontWeight: 600, fontSize: "0.95rem" },
  cardMeta: { color: "#777", fontSize: "0.8rem", marginTop: "0.15rem" },
  konf: { color: "#b5560a", fontSize: "0.72rem", marginTop: "0.2rem" },
};

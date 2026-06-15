import { useEffect, useState } from "react";
import { getPersonWithEvidence } from "./queries";
import type { FactWithEvidence, PersonWithEvidence } from "./types";

// PoC viser to personer: en almindelig (Gottschalk) og en med omstridt
// dødsdato (Stolberg), så evidenslaget bliver synligt i UI'et.
const PERSONS = ["Gottschalk von Reventlow", "Christian greve zu Stolberg-Stolberg"];

export default function App() {
  return (
    <main style={styles.page}>
      <header style={styles.header}>
        <h1 style={styles.h1}>DAA-følgesvend</h1>
        <p style={styles.sub}>Reventlow PoC · første app-skive (read-only)</p>
      </header>
      {PERSONS.map((navn) => (
        <PersonCard key={navn} visningNavn={navn} />
      ))}
    </main>
  );
}

function PersonCard({ visningNavn }: { visningNavn: string }) {
  const [data, setData] = useState<PersonWithEvidence | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    getPersonWithEvidence(visningNavn)
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(describeError(e)))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [visningNavn]);

  if (loading) return <section style={styles.card}>Henter «{visningNavn}»…</section>;
  if (error)
    return (
      <section style={{ ...styles.card, ...styles.cardError }}>
        <strong>Kunne ikke hente «{visningNavn}»</strong>
        <pre style={styles.pre}>{error}</pre>
      </section>
    );
  if (!data) return null;

  const { person, facts } = data;

  return (
    <section style={styles.card}>
      <h2 style={styles.h2}>{person.visning_navn ?? "(uden navn)"}</h2>
      <dl style={styles.meta}>
        <dt style={styles.dt}>Køn</dt>
        <dd style={styles.dd}>{person.koen ?? "ikke registreret"}</dd>
        <dt style={styles.dt}>Status</dt>
        <dd style={styles.dd}>{person.levende ? "levende" : "afdød"}</dd>
      </dl>

      <h3 style={styles.h3}>Fakta</h3>
      {facts.length === 0 ? (
        <p style={styles.empty}>Ingen fakta registreret.</p>
      ) : (
        <ul style={styles.factList}>
          {facts.map((f) => (
            <FactRow key={f.fact.id} item={f} />
          ))}
        </ul>
      )}
    </section>
  );
}

function FactRow({ item }: { item: FactWithEvidence }) {
  const { fact, assertions, conclusion, chosen } = item;
  const disputed = assertions.length > 1;

  return (
    <li style={styles.factItem}>
      <div style={styles.factHead}>
        <span style={styles.faktatype}>{fact.faktatype}</span>
        <span style={styles.chosenValue}>{displayValue(chosen)}</span>
        {disputed && <span style={styles.badge}>omstridt · {assertions.length} påstande</span>}
      </div>

      {/* Evidenslag: vises når der er konkurrerende påstande */}
      {disputed && (
        <div style={styles.evidence}>
          <div style={styles.evidenceLabel}>Påstande (uforanderlige kildeudsagn)</div>
          <ul style={styles.assertionList}>
            {assertions.map((a) => {
              const isChosen = chosen?.id === a.id;
              return (
                <li
                  key={a.id}
                  style={{ ...styles.assertionItem, ...(isChosen ? styles.assertionChosen : {}) }}
                >
                  <span>{displayValue(a)}</span>
                  {isChosen && <span style={styles.chosenTag}>blåstemplet</span>}
                </li>
              );
            })}
          </ul>
          {conclusion && (
            <div style={styles.conclusion}>
              <strong>Konklusion:</strong> {conclusion.status ?? "—"}
              {conclusion.blaastemplet_af ? ` · af ${conclusion.blaastemplet_af}` : ""}
            </div>
          )}
        </div>
      )}
    </li>
  );
}

// Dato-fakta viser rå dato-tekst; værdi-fakta viser teksten.
function displayValue(a: { vaerdi_tekst: string | null; date_raw: string | null } | null): string {
  if (!a) return "(ingen blåstemplet påstand)";
  return a.date_raw ?? a.vaerdi_tekst ?? "(tom)";
}

function describeError(e: unknown): string {
  // Supabase/PostgREST-fejl er plain objekter (PostgrestError), ikke Error.
  // String(obj) -> "[object Object]", så vi pakker felterne ud eksplicit.
  let msg: string;
  if (e instanceof Error) {
    msg = e.message;
  } else if (e && typeof e === "object") {
    const o = e as Record<string, unknown>;
    msg =
      [o.message, o.details, o.hint, o.code && `(code ${o.code})`]
        .filter(Boolean)
        .join(" · ") || JSON.stringify(o);
  } else {
    msg = String(e);
  }
  // PostgREST returnerer typisk tom/forbudt ved manglende RLS-læseadgang.
  if (/permission denied|row-level security|JWT|not find|relation|PGRST|0 rows|results contain/i.test(msg)) {
    return (
      msg +
      "\n\nMuligvis manglende læseadgang for anon-rollen (kør web/dev-rls.sql) " +
      "ELLER ingen seed-data i basen (kør supabase_load.R)."
    );
  }
  return msg;
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    fontFamily: "system-ui, -apple-system, Segoe UI, Roboto, sans-serif",
    maxWidth: 720,
    margin: "0 auto",
    padding: "2rem 1rem",
    color: "#1a1a1a",
  },
  header: { marginBottom: "1.5rem" },
  h1: { margin: 0, fontSize: "1.6rem" },
  sub: { margin: "0.25rem 0 0", color: "#666" },
  card: {
    border: "1px solid #e2e2e2",
    borderRadius: 10,
    padding: "1.25rem",
    marginBottom: "1.25rem",
    background: "#fff",
    boxShadow: "0 1px 2px rgba(0,0,0,0.04)",
  },
  cardError: { borderColor: "#e0b4b4", background: "#fcf3f3" },
  h2: { margin: "0 0 0.75rem", fontSize: "1.25rem" },
  h3: { margin: "1rem 0 0.5rem", fontSize: "0.95rem", color: "#444" },
  meta: { display: "grid", gridTemplateColumns: "auto 1fr", gap: "0.25rem 1rem", margin: 0 },
  dt: { color: "#888", fontSize: "0.85rem" },
  dd: { margin: 0, fontSize: "0.9rem" },
  factList: { listStyle: "none", padding: 0, margin: 0 },
  factItem: { padding: "0.5rem 0", borderTop: "1px solid #f0f0f0" },
  factHead: { display: "flex", alignItems: "baseline", gap: "0.6rem", flexWrap: "wrap" },
  faktatype: {
    fontSize: "0.75rem",
    textTransform: "uppercase",
    letterSpacing: "0.04em",
    color: "#7a7a7a",
    minWidth: 70,
  },
  chosenValue: { fontWeight: 600 },
  badge: {
    fontSize: "0.7rem",
    background: "#fff0e6",
    color: "#b5560a",
    borderRadius: 999,
    padding: "0.1rem 0.5rem",
  },
  evidence: {
    marginTop: "0.5rem",
    padding: "0.6rem 0.75rem",
    background: "#fafafa",
    borderRadius: 8,
    border: "1px solid #eee",
  },
  evidenceLabel: { fontSize: "0.72rem", color: "#999", marginBottom: "0.35rem" },
  assertionList: { listStyle: "none", padding: 0, margin: 0 },
  assertionItem: {
    display: "flex",
    justifyContent: "space-between",
    fontSize: "0.88rem",
    padding: "0.2rem 0",
    color: "#555",
  },
  assertionChosen: { color: "#1a1a1a", fontWeight: 600 },
  chosenTag: { fontSize: "0.7rem", color: "#2e7d32" },
  conclusion: { marginTop: "0.4rem", fontSize: "0.82rem", color: "#444" },
  empty: { color: "#999", fontSize: "0.9rem" },
  pre: { whiteSpace: "pre-wrap", fontSize: "0.8rem", margin: "0.5rem 0 0" },
};

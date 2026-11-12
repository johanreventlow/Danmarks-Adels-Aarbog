import React from "react";
import ReactDOM from "react-dom/client";
import Folgesvend from "./Folgesvend";
import { navigate, usePath } from "./router";
import { ErrorBoundary } from "./components/ErrorBoundary";
import "./fonts";
import "./base.css";

// Redaktørbordet lazy-loades: det hentes kun på /redaktion og ligger ikke i læsernes hoved-bundle.
const Redaktion = React.lazy(() => import("./Redaktion"));

// Path-route: alt under /redaktion er redaktørbordet; ellers publikums-følgesvenden.
function Root() {
  const path = usePath();
  // Engangs-migrering af gamle hash-baserede bogmærker (#redaktion) fra før path-routing.
  React.useEffect(() => {
    if (window.location.hash.startsWith("#redaktion")) {
      navigate("/redaktion", { replace: true });
    }
  }, []);
  if (!path.startsWith("/redaktion")) return <Folgesvend />;
  return (
    <React.Suspense fallback={<div role="status" style={{ padding: 24 }}>Indlæser redaktionen…</div>}>
      <Redaktion />
    </React.Suspense>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <Root />
    </ErrorBoundary>
  </React.StrictMode>,
);

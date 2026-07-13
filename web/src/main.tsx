import React from "react";
import ReactDOM from "react-dom/client";
import Folgesvend from "./Folgesvend";
import Redaktion from "./Redaktion";
import { navigate, usePath } from "./router";
import { ErrorBoundary } from "./components/ErrorBoundary";

// Path-route: alt under /redaktion er redaktørbordet; ellers publikums-følgesvenden.
function Root() {
  const path = usePath();
  // Engangs-migrering af gamle hash-baserede bogmærker (#redaktion) fra før path-routing.
  React.useEffect(() => {
    if (window.location.hash.startsWith("#redaktion")) {
      navigate("/redaktion", { replace: true });
    }
  }, []);
  return path.startsWith("/redaktion") ? <Redaktion /> : <Folgesvend />;
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <Root />
    </ErrorBoundary>
  </React.StrictMode>,
);

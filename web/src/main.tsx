import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import Redaktion from "./Redaktion";

// Minimal hash-route: #publikum = read-only publikumsvisning (App); ellers redaktørbordet.
function Root() {
  const [hash, setHash] = React.useState(window.location.hash);
  React.useEffect(() => {
    const on = () => setHash(window.location.hash);
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  return hash.startsWith("#publikum") ? <App /> : <Redaktion />;
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
);

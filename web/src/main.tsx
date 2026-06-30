import React from "react";
import ReactDOM from "react-dom/client";
import Folgesvend from "./Folgesvend";
import Redaktion from "./Redaktion";

// Hash-route: #redaktion = redaktørbordet; ellers publikums-følgesvenden.
function Root() {
  const [hash, setHash] = React.useState(window.location.hash);
  React.useEffect(() => {
    const on = () => setHash(window.location.hash);
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  return hash.startsWith("#redaktion") ? <Redaktion /> : <Folgesvend />;
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
);

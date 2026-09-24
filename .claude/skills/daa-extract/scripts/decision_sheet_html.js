"use strict";
// Redigeringsflade for afgørelsesarket (4.5). Eksportfunktionerne er rene og testes i
// node (test_decision_sheet_html.py); brugerfladen kører kun, når der er et document.
// Al data indsættes med textContent — aldrig innerHTML — fordi den er kildetekst.

var TOKS = ["A", "R", "U"];
var LINE_BREAKS = /[\r\n\t\u000b\u000c\u001c-\u001e\u0085\u2028\u2029]+/g;
var SPLIT_LINES = /[\r\n\u000b\u000c\u001c-\u001e\u0085\u2028\u2029]+/;

function sanitizeNote(s) {
  // parse_sheet bruger str.splitlines(): ethvert linjeskift ville afkorte noten.
  return String(s || "").replace(LINE_BREAKS, " ").trim();
}

function initialState(p) {
  var st = { toks: {}, notes: {}, mangler: {}, unplaced: p.unplaced || "" };
  p.items.forEach(function (it) {
    st.toks[it.id] = it.initial_tok;
    st.notes[it.id] = it.initial_note;
  });
  Object.keys(p.mangler || {}).forEach(function (k) { st.mangler[k] = p.mangler[k]; });
  return st;
}

function exportSheet(p, st) {
  st = st || initialState(p);
  var lines = p.sheet_lines.slice();
  p.items.forEach(function (it) {
    var tok = st.toks[it.id];
    if (TOKS.indexOf(tok) < 0) tok = "_";
    var note = sanitizeNote(st.notes[it.id]);
    lines[it.line] = "D " + it.id + " " + it.version + " : " + tok + (note ? " # " + note : "");
  });
  return lines.join("\n");
}

function splitLines(s) {
  return String(s || "").split(SPLIT_LINES).map(function (l) { return l.trim(); })
    .filter(function (l) { return l.length > 0; });
}

function exportMangler(p, st) {
  st = st || initialState(p);
  var out = ["# MANGLER (4.5): udsagn, modellen burde have fundet.",
             "# Postens nøgle først, derefter udsagnet — ét pr. linje."];
  p.posts.forEach(function (k) {
    splitLines(st.mangler[k]).forEach(function (l) { out.push(k + " " + l); });
  });
  splitLines(st.unplaced).forEach(function (l) { out.push(l); });
  return out.join("\n") + "\n";
}

// Rollen `other` betyder »ikke knyttet til postens hovedperson« (profilens
// persona_role_map: mention.*, relation.*, reference.*) — ikke at udsagnet handler
// om en anden person. Arkets signal hedder »anden person«; fladen viser, hvad det er.
// Mekanisk tjek (decision_sheet_html.verbatim): står værdien ordret i de citerede
// klausuler? Det afgør kun »står det der« — ikke typen eller personen.
var VERBATIM = {
  "ordret": ["✓ ordret", "ok", "Værdien står tegn for tegn i klausulen. Tjek stadig type og person."],
  "næsten": ["≈ næsten ordret", "warn", "Kun store/små bogstaver eller tegnsætning afviger fra klausulen."],
  "nej": ["✗ ikke ordret", "bad", "Værdien er omskrevet eller står ikke i klausulen. Se nøje efter."]
};
var ROLE_HELP = "Forslaget er kun, at dette nævnes i klausulen. Er det hovedpersonens bopæl, " +
  "fødested, gods el.lign., er det et eget forslag (person.*) — mangler det, skriv det i MANGLER. " +
  "Hvem/hvad omtalen konkret henviser til, afgøres i trin 5b.";
var MENTION = { place: "stedsomtale", person: "personomtale", estate: "godsomtale",
                organization: "omtale af organisation" };
function roleLabel(it) {
  var p = it.predicate;
  if (p.indexOf("mention.") === 0) return MENTION[p.slice(8)] || "omtale";
  if (p.indexOf("relation.") === 0) return "relation til anden person";
  if (p.indexOf("reference.") === 0) return "henvisning";
  return "ikke knyttet til hovedpersonen";
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { exportSheet: exportSheet, exportMangler: exportMangler,
                     initialState: initialState, sanitizeNote: sanitizeNote, roleLabel: roleLabel };
}

if (typeof document !== "undefined") (function () {
  var P = JSON.parse(document.getElementById("data").textContent);
  var KEY = "daa-afgoer:" + P.rows_sha256;
  var st = initialState(P);
  var resumed = false;
  try {
    var saved = JSON.parse(localStorage.getItem(KEY) || "null");
    if (saved && saved.toks) {
      var ok = P.items.every(function (it) { return it.id in saved.toks; });
      if (ok) { st = saved; resumed = true; }
    }
  } catch (e) { /* privat vindue eller blokeret lager: kør uden */ }

  function save() { try { localStorage.setItem(KEY, JSON.stringify(st)); } catch (e) {} }

  function el(tag, attrs, text) {
    var n = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (a) {
      if (a === "class") n.className = attrs[a]; else n.setAttribute(a, attrs[a]);
    });
    if (text !== undefined && text !== null) n.textContent = String(text);
    return n;
  }

  // --- header ---
  var header = el("header");
  header.appendChild(el("h1", null, "Afgørelsesark 4.5"));
  var stat = el("span", { class: "stat" });
  var bar = el("div", { class: "bar" }); var barFill = el("i"); bar.appendChild(barFill);
  var filter = el("select", { "aria-label": "Filter" });
  [["alle", "Alle forslag"], ["uafgjort", "Kun uafgjorte"], ["signal", "Kun »se nærmere«"],
   ["uanbefalet", "Kun uden anbefaling"], ["afviger", "Afviger fra anbefaling"],
   ["ikkeordret", "Kun ikke ordret (≈/✗)"], ["U", "Kun U (uafklaret)"]].forEach(function (o) {
    filter.appendChild(el("option", { value: o[0] }, o[1]));
  });
  var btnSheet = el("button", { class: "primary", type: "button" }, "Gem AFGØR");
  var btnMiss = el("button", { type: "button" }, "Gem MANGLER");
  var btnReset = el("button", { type: "button" }, "Brug arkets tilstand");
  [stat, bar, filter, btnSheet, btnMiss, btnReset].forEach(function (n) { header.appendChild(n); });
  document.body.appendChild(header);

  var main = el("main");
  var help = el("p", { class: "help" },
    "Taster: j/k = næste/forrige · a/r/u = afgør og gå videre · n = note · " +
    "c = vis/skjul postens klausuler · Esc = forlad felt. " +
    "Arbejdet gemmes løbende i browseren. »Gem AFGØR« kræver, at alle forslag er afgjort; " +
    "filen hentes som AFGØR-udfyldt.txt og skal flyttes til ~/.private/45-pilot/.");
  main.appendChild(help);
  if (resumed) main.appendChild(el("p", { class: "help" },
    "Genoptaget fra browserens gemte arbejde. »Brug arkets tilstand« kasserer det og " +
    "starter fra AFGØR.txt/MANGLER.txt, som siden blev bygget af."));
  document.body.appendChild(main);

  var itemNodes = [];   // {it, node, buttons, diff}
  var byPost = {};
  P.items.forEach(function (it) { (byPost[it.record_key] = byPost[it.record_key] || []).push(it); });

  P.posts.forEach(function (k) {
    var sec = el("section", { class: "post" });
    var h = el("h2", null, "Post " + k);
    h.appendChild(el("small", null, byPost[k].length + " forslag"));
    sec.appendChild(h);
    // Postens klausuler, som arket kender dem (alle forslags citater), så navnet og
    // sammenhængen kan ses fra et kort, der kun citerer en senere klausul.
    var clauses = (P.record_clauses || {})[k] || [];
    var ctx = el("details", { class: "ctx" });
    ctx.appendChild(el("summary", null, "Postens klausuler (" + clauses.length +
      " kendte — klausuler, intet forslag citerer, er ikke med) · tast c"));
    var cul = el("ul", { class: "cited" });
    var ctxLis = {};
    var prev = 0;
    clauses.forEach(function (c) {
      if (c.ordinal > prev + 1) cul.appendChild(el("li", { class: "gap" },
        "… klausul " + (prev + 1) + (c.ordinal - 1 > prev + 1 ? "–" + (c.ordinal - 1) : "") + " ikke citeret"));
      prev = c.ordinal;
      var li = el("li");
      li.appendChild(el("span", { class: "ord" }, "[" + c.ordinal + "]"));
      li.appendChild(document.createTextNode(c.text));
      if (c.predicates.length) li.appendChild(el("span", { class: "preds" }, c.predicates.join(", ")));
      if (c.flags.length) li.appendChild(el("span", { class: "flag" }, "flag: " + c.flags.join(", ")));
      ctxLis[c.ordinal] = li;
      cul.appendChild(li);
    });
    ctx.appendChild(cul);
    sec.appendChild(ctx);
    byPost[k].forEach(function (it) {
      var node = el("div", { class: "item", tabindex: "-1" });
      var head = el("div", { class: "head" });
      head.appendChild(el("span", { class: "pred" }, it.predicate));
      head.appendChild(el("span", { class: "val" }, it.value));
      head.appendChild(el("span", { class: "tag" }, "confidence " + it.confidence));
      var vb = VERBATIM[it.verbatim];
      if (vb) head.appendChild(el("span", { class: "tag " + vb[1], title: vb[2] }, vb[0]));
      head.appendChild(el("span", { class: "tag" },
        it.recommendation ? "anbefaling " + it.recommendation + " (4.3b)" : "ingen anbefaling"));
      it.signals.forEach(function (s) {
        var t = s === "anden person" ? roleLabel(it) : s;
        head.appendChild(el("span", { class: "tag warn", title: t === s ? "" : ROLE_HELP }, t));
      });
      var diff = el("span", { class: "diff hidden" }, "afviger fra anbefaling");
      head.appendChild(diff);
      node.appendChild(head);
      var toks = el("div", { class: "toks", role: "group", "aria-label": "Afgørelse" });
      var buttons = {};
      TOKS.forEach(function (t) {
        var b = el("button", { type: "button", "data-t": t, "aria-pressed": "false",
          title: { A: "Accepter", R: "Afvis", U: "Uafklaret" }[t] }, t);
        b.addEventListener("click", function () { setTok(it.id, t); focusItem(indexOf(it.id)); });
        buttons[t] = b; toks.appendChild(b);
      });
      node.appendChild(toks);
      var ul = el("ul", { class: "cited" });
      it.cited.forEach(function (c) {
        var li = el("li");
        li.appendChild(el("span", { class: "ord" }, "[" + c.ordinal + "]"));
        li.appendChild(document.createTextNode(c.text));
        if (c.flags && c.flags.length) li.appendChild(el("span", { class: "flag" }, "flag: " + c.flags.join(", ")));
        ul.appendChild(li);
      });
      node.appendChild(ul);
      var note = el("input", { class: "note", type: "text", placeholder: "Note (valgfri)",
        "aria-label": "Note" });
      note.value = st.notes[it.id] || "";
      note.addEventListener("input", function () { st.notes[it.id] = note.value; save(); });
      node.appendChild(note);
      node.addEventListener("click", function (e) {
        if (e.target === node) focusItem(indexOf(it.id));
      });
      sec.appendChild(node);
      itemNodes.push({ it: it, node: node, buttons: buttons, diff: diff, note: note, post: sec,
                       ctx: ctx, ctxLis: ctxLis });
    });
    var miss = el("div", { class: "miss" });
    var lab = el("label", null, "Udsagn i post " + k + ", som modellen manglede (ét pr. linje)");
    var ta = el("textarea", { rows: "2" });
    ta.value = st.mangler[k] || "";
    ta.addEventListener("input", function () { st.mangler[k] = ta.value; save(); });
    lab.appendChild(ta); miss.appendChild(lab); sec.appendChild(miss);
    main.appendChild(sec);
  });

  var unplacedBox = el("section", { class: "post" });
  unplacedBox.appendChild(el("h2", null, "Øvrige MANGLER-linjer"));
  var unTa = el("textarea", { rows: "3", "aria-label": "Øvrige MANGLER-linjer" });
  unTa.value = st.unplaced || "";
  unTa.addEventListener("input", function () { st.unplaced = unTa.value; save(); });
  unplacedBox.appendChild(el("p", { class: "help" },
    "Linjer fra MANGLER.txt, der ikke kunne knyttes til en post. Skriv selv nøglen først."));
  unplacedBox.appendChild(unTa);
  main.appendChild(unplacedBox);

  function indexOf(id) {
    for (var i = 0; i < itemNodes.length; i++) if (itemNodes[i].it.id === id) return i;
    return -1;
  }

  function matches(x) {
    var t = st.toks[x.it.id], f = filter.value;
    if (f === "uafgjort") return t === "_";
    if (f === "signal") return x.it.signals.length > 0;
    if (f === "uanbefalet") return !x.it.recommendation;
    if (f === "afviger") return !!x.it.recommendation && t !== "_" && t !== x.it.recommendation;
    if (f === "U") return t === "U";
    if (f === "ikkeordret") return x.it.verbatim !== "ordret";
    return true;
  }

  function paint(x) {
    var t = st.toks[x.it.id];
    TOKS.forEach(function (k) { x.buttons[k].setAttribute("aria-pressed", String(t === k)); });
    x.diff.classList.toggle("hidden", !(x.it.recommendation && t !== "_" && t !== x.it.recommendation));
  }

  function refresh() {
    var n = P.items.length, c = { A: 0, R: 0, U: 0, _: 0 };
    P.items.forEach(function (it) { c[st.toks[it.id]] = (c[st.toks[it.id]] || 0) + 1; });
    var done = n - c._;
    stat.textContent = "afgjort " + done + "/" + n + " · A " + c.A + " · R " + c.R + " · U " + c.U;
    barFill.style.width = (n ? (100 * done / n) : 0) + "%";
    btnSheet.disabled = c._ > 0;
    btnSheet.title = c._ > 0 ? c._ + " forslag mangler afgørelse" : "Hent AFGØR-udfyldt.txt";
    var visiblePosts = new Set();
    itemNodes.forEach(function (x) {
      var show = matches(x) || x.node.classList.contains("focus");
      x.node.classList.toggle("hidden", !show);
      if (show) visiblePosts.add(x.post);
    });
    itemNodes.forEach(function (x) { x.post.classList.toggle("hidden", !visiblePosts.has(x.post)); });
  }

  function setTok(id, t) {
    st.toks[id] = t; save();
    paint(itemNodes[indexOf(id)]);
    refresh();
  }

  var cur = -1;
  function focusItem(i) {
    if (i < 0 || i >= itemNodes.length) return;
    if (cur >= 0) itemNodes[cur].node.classList.remove("focus");
    cur = i;
    var x = itemNodes[i];
    x.node.classList.add("focus");
    // markér det fokuserede forslags egne klausuler i postens klausulliste
    Object.keys(x.ctxLis).forEach(function (o) { x.ctxLis[o].classList.remove("here"); });
    x.it.cited.forEach(function (c) { if (x.ctxLis[c.ordinal]) x.ctxLis[c.ordinal].classList.add("here"); });
    // én liste pr. post; står den åben, følger den det fokuserede kort
    if (x.ctx.open) x.post.insertBefore(x.ctx, x.node);
    x.node.focus({ preventScroll: true });
    x.node.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function step(d) {
    var i = cur;
    for (var k = 0; k < itemNodes.length; k++) {
      i += d;
      if (i < 0 || i >= itemNodes.length) return;
      if (matches(itemNodes[i])) { focusItem(i); return; }
    }
  }

  document.addEventListener("keydown", function (e) {
    var tag = (e.target && e.target.tagName) || "";
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") {
      if (e.key === "Escape") { e.target.blur(); if (cur >= 0) itemNodes[cur].node.focus(); }
      return;
    }
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    var k = e.key.toLowerCase();
    if (k === "j") { step(1); e.preventDefault(); }
    else if (k === "k") { step(-1); e.preventDefault(); }
    else if ((k === "a" || k === "r" || k === "u") && cur >= 0) {
      setTok(itemNodes[cur].it.id, k.toUpperCase()); step(1); e.preventDefault();
    } else if (k === "n" && cur >= 0) { itemNodes[cur].note.focus(); e.preventDefault(); }
    else if (k === "c" && cur >= 0) {
      var x = itemNodes[cur];
      x.ctx.open = !x.ctx.open;
      if (x.ctx.open) x.post.insertBefore(x.ctx, x.node);
      x.node.scrollIntoView({ block: "nearest" });
      e.preventDefault();
    }
  });

  function download(name, text) {
    var url = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
    var a = el("a", { href: url, download: name });
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  btnSheet.addEventListener("click", function () { download("AFGØR-udfyldt.txt", exportSheet(P, st)); });
  btnMiss.addEventListener("click", function () { download("MANGLER-udfyldt.txt", exportMangler(P, st)); });
  btnReset.addEventListener("click", function () {
    if (!confirm("Kassér browserens gemte arbejde og start fra arkets tilstand?")) return;
    try { localStorage.removeItem(KEY); } catch (e) {}
    location.reload();
  });
  filter.addEventListener("change", function () { refresh(); step(1); });

  itemNodes.forEach(paint);
  refresh();
  var first = itemNodes.findIndex(function (x) { return st.toks[x.it.id] === "_"; });
  focusItem(first >= 0 ? first : 0);
})();

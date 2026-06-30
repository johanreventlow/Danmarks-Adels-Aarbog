// Token-grammatik (spec §5.1): [[<type>:<id>|<visningstekst>]]
//   type ∈ fast vokabular; id heltal uden foranstillet nul; |[] escapes som \|\[\].
//   Malformet/uafsluttet/ukendt type → renderes som rå tekst (indekseres ikke, fejler ikke).
export type MentionType =
  | 'person' | 'estate' | 'place' | 'organisation' | 'source'
  | 'coat_of_arms' | 'family' | 'historical_event' | 'media' | 'lineage';

export type Segment =
  | { kind: 'text'; text: string }
  | { kind: 'link'; maalType: MentionType; maalId: number; label: string };

// type:id-hoved; label fanges manuelt frem til uescaped ]]
const HEAD = /\[\[(person|estate|place|organisation|source|coat_of_arms|family|historical_event|media|lineage):(0|[1-9][0-9]*)\|/;

// Escape-alfabet: \ | [ ] — backslash MED i klassen (review10 H1), så scanneren nedenfor
// (der altid behandler \<næste-tegn> som ÉT escaped 2-tegns-par) aldrig kan fejltolke en
// ueskaperet trailing backslash som starten på et escape af afgrænserens første ']'.
function unescape(s: string): string {
  return s.replace(/\\([\\|[\]])/g, '$1');
}

export function parseNarrativ(text: string): Segment[] {
  const out: Segment[] = [];
  let rest = text ?? '';
  let buf = '';
  while (rest.length > 0) {
    const m = HEAD.exec(rest);
    if (!m || m.index !== 0) {
      // ingen token ved start: flyt tekst frem til næste mulige token (mindst ét tegn)
      // m===null → nextStart=rest.length>=1 (while-vagten); m findes → m.index!==0 → m.index>=1.
      // nextStart er altså her altid >=1; intet Math.max-gulv nødvendigt.
      const nextStart = m ? m.index : rest.length;
      buf += rest.slice(0, nextStart);
      rest = rest.slice(nextStart);
      continue;
    }
    // find uescaped ]] efter hovedet
    const after = rest.slice(m[0].length);
    let i = 0;
    let label = '';
    let closed = false;
    while (i < after.length) {
      if (after[i] === '\\' && i + 1 < after.length) { label += after.slice(i, i + 2); i += 2; continue; }
      if (after[i] === ']' && after[i + 1] === ']') { closed = true; break; }
      label += after[i]; i += 1;
    }
    // m[1] er altid et gyldigt vokabular-medlem her — HEAD's alternation begrænser allerede
    // capture-gruppen til de 10 kendte typer; ukendt type matcher HEAD slet ikke (m===null).
    if (!closed) { // malformet (uafsluttet) → rå tekst (ét tegn ad gangen)
      buf += rest[0]; rest = rest.slice(1); continue;
    }
    if (buf) { out.push({ kind: 'text', text: buf }); buf = ''; }
    out.push({ kind: 'link', maalType: m[1] as MentionType, maalId: Number(m[2]), label: unescape(label) });
    rest = after.slice(i + 2);
  }
  if (buf) out.push({ kind: 'text', text: buf });
  return out;
}

// Byg et token; escaper \|[] i visningsteksten (omvendt af parseNarrativ's unescape).
// Backslash skal escapes FØRST (review10 H1) — ellers ville en literal backslash i
// labelen blive fejltolket af scanneren som start på et escape af det følgende tegn.
export function makeToken(type: MentionType, id: number, label: string): string {
  const esc = label.replace(/[\\|[\]]/g, (ch) => `\\${ch}`);
  return `[[${type}:${id}|${esc}]]`;
}

// Indsæt tekst ved cursor-position; klamp position til [0, len]; returnér ny tekst + cursor.
export function insertAt(text: string, pos: number, insert: string): { text: string; cursor: number } {
  const p = Math.max(0, Math.min(pos, text.length));
  return { text: text.slice(0, p) + insert + text.slice(p), cursor: p + insert.length };
}

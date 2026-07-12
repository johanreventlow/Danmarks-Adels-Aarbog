// PORTERET fra mobile/src/lib/mentions.ts — hold i sync (ren TS, ingen RN-afhængighed).
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

// Blok-gruppering (billeder-i-narrativer 2026-07-05, Slice C) — minimal, håndrullet udvidelse af
// grammatikken OVEN PÅ parseNarrativ's segmenter (tokeniseret FØRST, aldrig line-splittet på rå
// tekst — undgår at et token der tilfældigvis indeholder et linjeskift i sin label fejltolkes).
// Ingen markdown-bibliotek: kun `##`/`###`-linjer som overskrift + linjeskift/blanke-linjer som
// afsnitsgrænser. `media`-tokens bliver ALTID deres egen blok (kan ikke sidde inline i tekstflowet
// på mobile — RN tillader ikke <Image> som barn af <Text>); andre mention-typer (fx person) forbliver
// inline i det løbende afsnit, uændret adfærd.
export type Block =
  | { kind: 'heading'; level: 2 | 3; text: string }
  | { kind: 'paragraph'; segs: Segment[] }
  | { kind: 'media'; maalId: number; label: string };

// Overskrift SKAL stå alene på sin linje uden foranstillet whitespace (ingen indrykning-tolerance
// — holder reglen simpel og entydig, jf. "minimal, ikke fuld markdown").
const HEADING = /^(#{2,3})\s+(.+?)\s*$/;

// Slår en ny tekst-linje sammen med bufferens sidste segment hvis det allerede er tekst (undgår at
// et flerlinjet afsnit bliver til N separate tekst-segmenter — bevarer i stedet ÉT segment med
// indlejrede '\n', som renderen viser som linjeskift INDEN i afsnittet).
function pushText(buf: Segment[], text: string): void {
  const last = buf[buf.length - 1];
  if (last && last.kind === 'text') last.text += text;
  else buf.push({ kind: 'text', text });
}

export function groupBlocks(segments: Segment[]): Block[] {
  const blocks: Block[] = [];
  let buf: Segment[] = [];
  const flush = () => {
    // dropper et afsnit der kun består af whitespace (fx to blanke linjer i træk)
    if (buf.length && !buf.every((s) => s.kind === 'text' && s.text.trim() === '')) {
      blocks.push({ kind: 'paragraph', segs: buf });
    }
    buf = [];
  };
  for (const seg of segments) {
    if (seg.kind === 'link' && seg.maalType === 'media') {
      flush();
      blocks.push({ kind: 'media', maalId: seg.maalId, label: seg.label });
      continue;
    }
    if (seg.kind === 'link') {
      buf.push(seg); // ikke-media mention (fx person) forbliver inline i det løbende afsnit
      continue;
    }
    seg.text.split('\n').forEach((line, i) => {
      const heading = HEADING.exec(line);
      if (heading) {
        flush();
        blocks.push({ kind: 'heading', level: heading[1].length as 2 | 3, text: heading[2] });
        return;
      }
      if (line.trim() === '') { flush(); return; }
      // i>0: linjen er en fortsættelse af FORRIGE linje i samme tekst-segment — men kun hvis den
      // forrige linje reelt landede i det løbende afsnit (buf ikke lige tømt af overskrift/blank).
      if (i > 0 && buf.length) pushText(buf, '\n');
      pushText(buf, line);
    });
  }
  flush();
  return blocks;
}

// PORTERET-koncept fra mobile/src/components/NarrativRenderer.tsx (web har ingen router — bruger
// en onPickPerson-callback i stedet for expo-router). Samme adfærd som mobile: kun 'person'-tokens
// er klikbare, øvrige typer vises som inaktiv tekst.
import { parseNarrativ } from '../lib/mentions';

export function NarrativRenderer(props: {
  tekst: string;
  onPickPerson: (id: string) => void;
  linkColor: string;
  inactiveColor: string;
}) {
  const { tekst, onPickPerson, linkColor, inactiveColor } = props;
  const segs = parseNarrativ(tekst);
  return (
    <span>
      {segs.map((s, i) => {
        if (s.kind === 'text') return <span key={i}>{s.text}</span>;
        if (s.maalType === 'person') {
          return (
            <span
              key={i}
              onClick={() => onPickPerson(String(s.maalId))}
              style={{ color: linkColor, textDecoration: 'underline', cursor: 'pointer' }}
            >
              {s.label}
            </span>
          );
        }
        return <span key={i} style={{ color: inactiveColor }}>{s.label}</span>;
      })}
    </span>
  );
}

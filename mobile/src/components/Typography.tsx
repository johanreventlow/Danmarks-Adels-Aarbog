// Genbrugelige tekst-primitiver bundet til design-tokens (§6). Holder font-familier +
// letter-spacing konsistent, så skærmene ikke gentager StyleSheet-boilerplate.
// NB: size-prop angiver prototypens størrelse — scaleType løfter den rendrede størrelse
// (se tokens.ts). En eksplicit fontSize i style-prop'en omgår løftet.
import { Text, type TextProps, type TextStyle } from 'react-native';
import { Colors, Fonts, monoSpacing, scaleType } from '../theme/tokens';

type Props = TextProps & { color?: string; size?: number; italic?: boolean };

// Mono kicker/label — uppercase, letter-spacing, dæmpet som standard.
export function Kicker({ style, color = Colors.textMuted, size = 10, ...rest }: Props) {
  const fs = scaleType(size);
  const s: TextStyle = {
    fontFamily: Fonts.mono,
    fontSize: fs,
    letterSpacing: monoSpacing(fs),
    textTransform: 'uppercase',
    color,
  };
  return <Text {...rest} style={[s, style]} />;
}

// Mono labels/årstal (ikke nødvendigvis uppercase).
export function Mono({ style, color = Colors.textMuted, size = 11, ...rest }: Props) {
  const fs = scaleType(size);
  const s: TextStyle = {
    fontFamily: Fonts.mono,
    fontSize: fs,
    letterSpacing: monoSpacing(fs, 0.1),
    color,
  };
  return <Text {...rest} style={[s, style]} />;
}

// Cormorant — overskrifter/navne.
export function Serif({ style, color = Colors.ink, size = 24, italic = false, ...rest }: Props) {
  const s: TextStyle = {
    fontFamily: italic ? Fonts.serifItalic : Fonts.serifSemi,
    fontSize: scaleType(size),
    color,
  };
  return <Text {...rest} style={[s, style]} />;
}

// Hanken Grotesk SemiBold — knap-/UI-labels (README §6: "knapper" = Hanken Grotesk).
// IKKE Mono — Mono er kun til kickers/årstal/labels med letter-spacing.
export function BtnLabel({ style, color = Colors.ink, size = 13, ...rest }: Props) {
  const s: TextStyle = {
    fontFamily: Fonts.sansSemi,
    fontSize: scaleType(size),
    color,
  };
  return <Text {...rest} style={[s, style]} />;
}

// Hanken Grotesk — brødtekst/UI.
export function Body({ style, color = Colors.textSecondary, size = 14, ...rest }: Props) {
  const fs = scaleType(size);
  const s: TextStyle = {
    fontFamily: Fonts.sans,
    fontSize: fs,
    lineHeight: fs * 1.5,
    color,
  };
  return <Text {...rest} style={[s, style]} />;
}

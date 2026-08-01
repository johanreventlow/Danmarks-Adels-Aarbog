// Ægte links. Al navigation i web-fladen gik tidligere gennem <div onClick>/<span onClick>, hvilket
// koster højreklik → "åbn i nyt vindue", cmd/ctrl-klik, midterklik og tastaturfokus. Denne primitiv
// renderer et rigtigt <a href> og afgiver klikket til browseren når brugeren har bedt om det.
//
// Højreklik (contextmenu) og midterklik (auxclick) fyrer ALDRIG Reacts onClick — de virker i det
// øjeblik elementet har et href, og kræver ingen kode her.
//
// Ligger ved siden af router.ts (routing-infrastruktur), ikke i components/primitives.tsx, som er
// Følgesvend-scoped og ikke importeres af Redaktion.tsx.
import type { AnchorHTMLAttributes, CSSProperties, MouseEvent, ReactNode } from 'react';
import { navigate } from './router';

// Skal browserens egen klik-adfærd have forrang? Ja hvis en indre handler allerede har taget
// klikket, hvis det ikke er venstreklik, eller hvis en modifier-tast er nede (ny fane/nyt vindue).
export function isModifiedClick(e: MouseEvent): boolean {
  return e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey;
}

// onNavigate: kaldesteder der gør MERE end at skifte URL (sætter state, kalder afslut(), bruger
// replace frem for push) beholder deres handler her og får modifier-klik oveni. Uden onNavigate
// navigerer Link selv til href.
// stopPropagation: sæt når ankeret sidder inde i et kort der har sin egen onClick.
export function Link({ href, onNavigate, stopPropagation = false, style, target, children, ...rest }:
  Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'onClick'> & {
    href: string;
    onNavigate?: () => void;
    stopPropagation?: boolean;
  }) {
  return (
    <a
      href={href}
      target={target}
      {...rest}
      onClick={(e) => {
        // FØR alt andet: også når browseren overtager klikket, må et omsluttende kort ikke
        // navigere den aktuelle fane — ellers gør et cmd-klik begge dele på én gang.
        if (stopPropagation) e.stopPropagation();
        if (isModifiedClick(e)) return;            // browseren åbner selv ny fane/nyt vindue
        if (target && target !== '_self') return;  // eksplicit ny fane — browseren ejer klikket
        e.preventDefault();
        if (onNavigate) onNavigate();
        else navigate(href);
      }}
      // Ankerets browser-default (blå + understregning) ville bryde designet; farve/dekoration
      // sættes af kaldestedet via style, præcis som de <span>'s der erstattes.
      style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer', ...style }}
    >
      {children}
    </a>
  );
}

// Kort/flader hvor HELE fladen er målet: er målet adresserbart, bliver fladen et ægte anker —
// ellers beholder den sin hidtidige <div onClick>. Samlet ét sted, fordi de tre kaldesteder
// (PersonCard, feed-kortene, forsidens månedens-gods) ellers gentog samme gren med hver sin
// lille afvigelse.
//
// display er en DEFAULT, ikke en overstyring: <a> er inline, så en flade uden eget display skal
// blokke — men en flade der selv layouter (våben-kortet er flex) beholder sit eget. Omvendt
// rækkefølge kostede våben-kortet dets side-om-side-layout.
//
// cursor sættes KUN i div-grenen; Link sætter den selv.
//
// Ingen stopPropagation her: alle tre kaldesteder er yderste flade. Får et kort inde i et andet
// kort brug for den, tager Link den direkte — og så følger et kaldested med der viser hvorfor.
export function KlikbarFlade({ href, onClick, style, children }: {
  href?: string | null;
  onClick?: () => void;
  style?: CSSProperties;
  children: ReactNode;
}) {
  if (href) {
    return (
      <Link href={href} onNavigate={onClick} style={{ display: 'block', ...style }}>
        {children}
      </Link>
    );
  }
  return <div onClick={onClick} style={{ ...style, cursor: onClick ? 'pointer' : 'default' }}>{children}</div>;
}

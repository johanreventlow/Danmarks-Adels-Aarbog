// Kolonne-kontrakten for public.media (review 37 S8 + R37S8-1, #397).
//
// MEDIA_KLIENT_KOLONNER er PRÆCIS kolonnelisten i db-rls.sql-blokken $review37_s8_anon_kolonner$
// (`GRANT SELECT (…) ON TABLE public.media TO anon, authenticated`). Klienten må kun vælge og filtrere på disse
// kolonner direkte (PostgREST); alt andet giver »permission denied« — også for redaktøren, fordi medlemmer og redaktion
// deler databaserollen authenticated. original_filnavn og sha256 er bevidst IKKE med: redaktionen læser dem gennem de
// rolle-gatede RPC'er red_media_interne_felter (medielisten) og red_media_efter_sha (dublettjekket).
// packages/core/src/__tests__/mediaKolonner.test.ts holder listen, db-rls.sql og alle media-forespørgsler i mobile/src i trit
// (web har sin egen kopi i web/src/data/mediaKontrakt.ts; testen kræver, at begge er lig db-rls.sql-listen).
export const MEDIA_KLIENT_KOLONNER = [
  'id', 'slags', 'titel', 'kunstner', 'datering', 'bucket', 'storage_path', 'mime_type', 'byte_size',
  'bredde', 'hoejde', 'upload_status', 'maa_publiceres', 'rettigheder_status', 'created_at',
] as const;

// De objekttyper et billede kan afbilde (media → objekt, rolle 'afbildet'). Samme kanoniske par som red_relation,
// red_slet_medierelation_uden_evidens og CHECK'en relation_afbildet_kanonisk (review 37 S4/R37B-3).
export const MEDIA_AFBILDET_OBJEKT_TYPER = ['estate', 'coat_of_arms', 'lineage', 'family', 'place'] as const;
export type MediaAfbildetObjektType = (typeof MEDIA_AFBILDET_OBJEKT_TYPER)[number];

// Klienterne beder om de interne felter i bidder; serverens loft er 1000 id'er pr. kald (22023 derover).
export const MEDIA_INTERNE_FELTER_BID = 500;

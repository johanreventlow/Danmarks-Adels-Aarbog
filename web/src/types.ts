// Typer der afspejler schema.sql. Kun de felter app-skiven læser.
// Bemærk: visning_*-felterne er en envejs-cache (afledt af konklusioner)
// og behandles som READ-ONLY i frontend — vi skriver dem aldrig.

export interface Person {
  id: number;
  levende: boolean;
  koen: string | null;
  visning_navn: string | null;
  visning_foedt: string | null;
  visning_doed: string | null;
  visning_titel: string | null;
}

export interface Fact {
  id: number;
  subjekt_type: string;
  subjekt_id: number;
  faktatype: string;
  sted_id: number | null;
}

// Påstand = én kildes uforanderlige udsagn om et fact/relation.
export interface Assertion {
  id: number;
  target_type: string;
  target_id: number;
  vaerdi_tekst: string | null;
  date_min: string | null;
  date_max: string | null;
  date_qualifier: string | null;
  date_raw: string | null;
}

// Konklusion = den blåstemplede vurdering ovenpå påstandene.
export interface Conclusion {
  id: number;
  target_type: string;
  target_id: number;
  valgt_assertion_id: number | null;
  status: string | null;
  blaastemplet_af: string | null;
}

// Sammensat visningsmodel: ét fact med alle dets påstande + konklusion.
export interface FactWithEvidence {
  fact: Fact;
  assertions: Assertion[];
  conclusion: Conclusion | null;
  // den valgte (blåstemplede) påstand, slået op fra konklusionen
  chosen: Assertion | null;
}

export interface PersonWithEvidence {
  person: Person;
  facts: FactWithEvidence[];
}

import { supabase } from "./supabase";
import type {
  Assertion,
  Conclusion,
  Fact,
  FactWithEvidence,
  Person,
  PersonWithEvidence,
} from "./types";

// Henter én person + alle dens fakta, hvert fact beriget med sine påstande
// og sin konklusion. Fordi fact<->assertion-linket er POLYMORFT uden hård FK
// (assertion.target_type='fact' AND target_id=fact.id), kan PostgREST ikke
// auto-embedde det — vi henter hvert lag og joiner i JS.
export async function getPersonWithEvidence(
  visningNavn: string,
): Promise<PersonWithEvidence> {
  // 1) personen (via den afledte visnings-cache)
  const { data: person, error: pErr } = await supabase
    .from("person")
    .select("id, levende, koen, visning_navn, visning_foedt, visning_doed, visning_titel")
    .eq("visning_navn", visningNavn)
    .single<Person>();

  if (pErr) throw pErr;
  if (!person) throw new Error(`Ingen person fundet med visning_navn '${visningNavn}'.`);

  // 2) personens fakta
  const { data: facts, error: fErr } = await supabase
    .from("fact")
    .select("id, subjekt_type, subjekt_id, faktatype, sted_id")
    .eq("subjekt_type", "person")
    .eq("subjekt_id", person.id)
    .returns<Fact[]>();

  if (fErr) throw fErr;
  const factList = facts ?? [];
  const factIds = factList.map((f) => f.id);

  if (factIds.length === 0) {
    return { person, facts: [] };
  }

  // 3) alle påstande for disse fakta (polymorft link, joines i JS)
  const { data: assertions, error: aErr } = await supabase
    .from("assertion")
    .select("id, target_type, target_id, vaerdi_tekst, date_min, date_max, date_qualifier, date_raw")
    .eq("target_type", "fact")
    .in("target_id", factIds)
    .returns<Assertion[]>();

  if (aErr) throw aErr;

  // 4) konklusioner for disse fakta
  const { data: conclusions, error: cErr } = await supabase
    .from("conclusion")
    .select("id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af")
    .eq("target_type", "fact")
    .in("target_id", factIds)
    .returns<Conclusion[]>();

  if (cErr) throw cErr;

  // 5) saml lagene pr. fact
  const assertionList = assertions ?? [];
  const conclusionByTarget = new Map<number, Conclusion>();
  for (const c of conclusions ?? []) conclusionByTarget.set(c.target_id, c);

  const enriched: FactWithEvidence[] = factList.map((fact) => {
    const factAssertions = assertionList.filter((a) => a.target_id === fact.id);
    const conclusion = conclusionByTarget.get(fact.id) ?? null;
    const chosen =
      (conclusion &&
        factAssertions.find((a) => a.id === conclusion.valgt_assertion_id)) ||
      null;
    return { fact, assertions: factAssertions, conclusion, chosen };
  });

  return { person, facts: enriched };
}

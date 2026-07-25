// GDPR-nødbremse for feedet — uafhængig af RLS' person_offentlig (db-rls.sql). `person.levende`
// er en ren manuel redaktør-markering (schema.sql) der ALDRIG genberegnes automatisk ud fra
// fødsels-/dødsdato. Denne gate kræver derfor POSITIV dødsevidens (dødsår, eller fødsel for
// længe siden til at være i live) før en person optræder i feedets person-identificerende kort —
// mangler evidens, udelades personen (fail-closed), selvom RLS allerede skulle have udelukket dem.
import type { Model } from './types';

// Ingen kendt person i slægten er dokumenteret ældre — over denne grænse regnes fødsel uden
// dødsår som sikker død, ikke som "muligvis i live".
export const LEVENDE_ALDERSGRAENSE = 120;

export function erSikkertDoed(p: { born: number | null; died: number | null }, dagsAar: number): boolean {
  if (p.died != null) return true;
  return p.born != null && dagsAar - p.born > LEVENDE_ALDERSGRAENSE;
}

// Udtynder model.persons/byId til kun sikkert-døde personer FØR modellen når frem til nogen
// person-identificerende visning. Navngivet efter hvad den RETURNERER (kun de sikkert-døde),
// ikke hvad den udelukker — i en GDPR-kritisk fil er den distinktion vigtig for næste læser.
// `indexes` (parentsByChild/spousesBy/...) rører vi bevidst ikke — slægtskabsstien
// (buildSlaegt → computeRelationship i @daa/core) skal fortsat kunne traversere den fulde
// ane-graf, ellers knækker "Er I i familie?" for stort set alle par. Builderne der slår personer
// op via model.byId (arkiv/forbundet/embede/historie) har allerede defensive
// `if (!byId[id]) continue`-guards, så en udtyndet byId er nok til at holde alle
// person-identificerende kort-typer sikre uden at ændre deres logik.
export function kunSikkertDoede(model: Model, dagsAar: number): Model {
  const persons = model.persons.filter((p) => erSikkertDoed(p, dagsAar));
  const byId: Model['byId'] = {};
  for (const p of persons) byId[p.id] = p;
  return { ...model, persons, byId };
}

export const ENTITY_DESCRIPTION_SUBJECTS = [
  'person', 'slaegt', 'lineage', 'coat_of_arms', 'media', 'estate',
] as const;

export type EntityDescriptionSubject = typeof ENTITY_DESCRIPTION_SUBJECTS[number];

export type PublicDescriptionCitation = {
  sourceLabel: string;
  citationLabel: string;
};

export function isEntityDescriptionSubject(value: string): value is EntityDescriptionSubject {
  return (ENTITY_DESCRIPTION_SUBJECTS as readonly string[]).includes(value);
}

/** Private source-record IDs må aldrig krydse den offentlige read-grænse. */
export function publicDescriptionCitation(input: PublicDescriptionCitation & { sourceRecordId?: string }): PublicDescriptionCitation {
  return { sourceLabel: input.sourceLabel, citationLabel: input.citationLabel };
}

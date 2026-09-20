import { physicalPersonIds, type Provenance } from '@daa/core';

export function personMemberIds(
  canonicalId: string,
  person?: { mergedFrom?: ReadonlyArray<Provenance> },
): string[] {
  return physicalPersonIds(canonicalId, person?.mergedFrom);
}

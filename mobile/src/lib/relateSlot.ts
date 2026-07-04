// Afgør hvilket slot (A/B) "sæt mig"-genvejen på slægtskabs-siden skal udfylde. Ren funktion —
// ingen model/React — så den kan enhedstestes uafhængigt af komponenten.
export function chooseMeSlot(relA: string | null, relB: string | null, meId: string): 'A' | 'B' | null {
  if (relA === meId || relB === meId) return null; // "mig" sidder allerede i et af felterne
  if (!relA) return 'A'; // A tom (eller intet valgt endnu) → udfyld A
  return 'B'; // A optaget → udfyld/erstat B, A er ankeret (fx fra en profils "Slægtskab"-knap)
}

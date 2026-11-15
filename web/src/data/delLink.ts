// Del et link (fase 9, mobil web): på telefonen med telefonens egen delemenu, ellers kopieres linket.
// Afbryder læseren delemenuen, sker intet andet. Fejler delingen af anden grund, prøves kopiering; Safari kan afvise
// den efter et asynkront delekald, og så er udfaldet »fejl« — siden beder læseren kopiere adressen selv.
export type DelUdfald = 'delt' | 'kopieret' | 'afbrudt' | 'fejl';

async function kopier(url: string): Promise<DelUdfald> {
  try {
    if (!navigator.clipboard?.writeText) return 'fejl';
    await navigator.clipboard.writeText(url);
    return 'kopieret';
  } catch { return 'fejl'; }
}

export async function delLink(url: string, titel: string, brugDeling: boolean): Promise<DelUdfald> {
  if (brugDeling && typeof navigator.share === 'function') {
    try {
      await navigator.share({ title: titel, url });
      return 'delt';
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') return 'afbrudt';
    }
  }
  return kopier(url);
}

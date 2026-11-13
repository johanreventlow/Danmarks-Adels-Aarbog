// Slægtens lille mærke (slægtsbjælken, slægtsregistret, personsidens slægtskort): våbnets sepia-
// gengivelse, når slægten har en (SLAEGTER[].vaaben.maerke), ellers det monogram, stedet viste før.
// Dekorativt: navnet står altid ved siden af, så billedet har tom alt og aria-hidden.
import type { ReactNode } from 'react';
import type { Slaegt } from '../data/nav';

export function SlaegtsMaerke({ slaegt, size, monogram }: { slaegt: Slaegt; size: number; monogram: ReactNode }) {
  const src = slaegt.vaaben?.maerke;
  if (!src) return <>{monogram}</>;
  return <img src={src} alt="" aria-hidden="true" width={size} height={size} style={{ display: 'block', width: size, height: size, objectFit: 'contain', flex: 'none' }} />;
}

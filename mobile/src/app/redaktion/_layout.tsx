// Redaktions-segment: egen Stack, skjult header (skærme har egen hero/TopBar). Adskilt fra
// publikums-(tabs). person/[id] pushes uden for tabbaren (spec §2).
import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { useStore } from '../../store/useStore';

export default function RedaktionLayout() {
  const rolle = useStore((s) => s.rolle);
  const redaktionStatus = useStore((s) => s.redaktionStatus);
  const loadRedaktionModel = useStore((s) => s.loadRedaktionModel);
  useEffect(() => {
    if (rolle === 'redaktion' && redaktionStatus === 'idle') loadRedaktionModel();
  }, [rolle, redaktionStatus, loadRedaktionModel]);

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(red-tabs)" />
      <Stack.Screen name="person/[id]" />
      <Stack.Screen name="entitet/person" />
      <Stack.Screen name="entitet/[type]" />
      <Stack.Screen name="sammenlign" />
    </Stack>
  );
}

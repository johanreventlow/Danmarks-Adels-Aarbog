// Redaktions-segment: egen Stack, skjult header (skærme har egen hero/TopBar). Adskilt fra
// publikums-(tabs). person/[id] pushes uden for tabbaren (spec §2).
import { Stack } from 'expo-router';

export default function RedaktionLayout() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(red-tabs)" />
      <Stack.Screen name="person/[id]" />
    </Stack>
  );
}

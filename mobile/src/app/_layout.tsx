// Root-layout: loader fonte (holder splash), initialiserer data-store, wrapper i
// gesture-root (variant C senere) + safe-area, og lægger tekstur-overlay øverst i z-stakken.
import { Stack, type ErrorBoundaryProps } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { Pressable, View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { TextureOverlay } from '../components/TextureOverlay';
import { Body, BtnLabel, Serif } from '../components/Typography';
import { useStore } from '../store/useStore';
import { useAppFonts } from '../theme/fonts';
import { Colors, Radius } from '../theme/tokens';

SplashScreen.preventAutoHideAsync().catch(() => {});

// Eksplicit fejl-fald-tilbage for rod-layoutet (review 27 R3). expo-router pakker enhver
// route-fil der eksporterer en navngivet `ErrorBoundary` ind i sin egen fejlgrænse (Try/
// getDerivedStateFromError) og gen-renderer denne ved render-fejl i stedet for den
// indbyggede, u-redaktionelle standardvisning. `retry` nulstiller fejl-tilstanden og
// forsøger at rendere routen igen.
export function ErrorBoundary({ error, retry }: ErrorBoundaryProps) {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg, alignItems: 'center', justifyContent: 'center', padding: 32, gap: 12 }}>
      <Serif size={22} style={{ textAlign: 'center' }}>Der opstod en fejl</Serif>
      <Body color={Colors.textMuted} style={{ textAlign: 'center' }}>{error.message}</Body>
      <Pressable
        onPress={retry}
        style={{ marginTop: 12, backgroundColor: Colors.bordeaux, borderRadius: Radius.field, paddingVertical: 12, paddingHorizontal: 24 }}>
        <BtnLabel color={Colors.paperCard}>Prøv igen</BtnLabel>
      </Pressable>
    </View>
  );
}

export default function RootLayout() {
  const fontsLoaded = useAppFonts();
  const load = useStore((s) => s.load);
  const hydrateMe = useStore((s) => s.hydrateMe);
  const hydrateAuth = useStore((s) => s.hydrateAuth);

  useEffect(() => {
    hydrateMe();
    hydrateAuth(); // genskab logget-ind session fra storage ved boot/reload (ellers "glemmes" login)
    load();
  }, [hydrateMe, hydrateAuth, load]);

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync().catch(() => {});
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
          <Stack
            screenOptions={{
              headerShown: false,
              contentStyle: { backgroundColor: Colors.paperBg },
            }}>
            <Stack.Screen name="(tabs)" />
            <Stack.Screen name="person/[id]" options={{ presentation: 'card' }} />
            <Stack.Screen name="about" />
            <Stack.Screen name="estates" />
            <Stack.Screen name="estate/[id]" />
            <Stack.Screen name="arms" />
            <Stack.Screen name="bogmaerker" />
          </Stack>
          <TextureOverlay />
        </View>
        <StatusBar style="dark" />
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

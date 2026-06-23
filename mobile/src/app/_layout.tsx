// Root-layout: loader fonte (holder splash), initialiserer data-store, wrapper i
// gesture-root (variant C senere) + safe-area, og lægger tekstur-overlay øverst i z-stakken.
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { TextureOverlay } from '../components/TextureOverlay';
import { useStore } from '../store/useStore';
import { useAppFonts } from '../theme/fonts';
import { Colors } from '../theme/tokens';

SplashScreen.preventAutoHideAsync().catch(() => {});

export default function RootLayout() {
  const fontsLoaded = useAppFonts();
  const load = useStore((s) => s.load);
  const hydrateMe = useStore((s) => s.hydrateMe);

  useEffect(() => {
    hydrateMe();
    load();
  }, [hydrateMe, load]);

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
          </Stack>
          <TextureOverlay />
        </View>
        <StatusBar style="dark" />
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

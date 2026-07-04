// Redaktions-tabbar: Følgesvend · Oversigt · Entiteter · Tilføj · Konto (spec §2 + vej-ud-tilføjelse).
// "Tilføj" og "Følgesvend" navigerer ikke til egne skærme — de intercepter tabPress
// (opret-sheet, hhv. forlad redaktionen til publikums-fanerne).
import { Ionicons } from '@expo/vector-icons';
import { Tabs, useRouter } from 'expo-router';
import { useState } from 'react';
import type { ColorValue } from 'react-native';
import { OpretSheet } from '../../../components/redaktion/OpretSheet';
import { Border, Colors, Fonts } from '../../../theme/tokens';

type IconName = keyof typeof Ionicons.glyphMap;
const icon = (name: IconName) => ({ color, size }: { color: ColorValue; size: number }) =>
  <Ionicons name={name} color={color as string} size={size} />;

export default function RedTabsLayout() {
  const router = useRouter();
  const [opretOpen, setOpretOpen] = useState(false);
  return (
    <>
      <Tabs
        screenOptions={{
          headerShown: false,
          tabBarActiveTintColor: Colors.bordeaux,
          tabBarInactiveTintColor: Colors.textMuted2,
          tabBarStyle: { height: 66, paddingTop: 8, paddingBottom: 10,
            backgroundColor: Colors.ink, borderTopColor: Border.medium },
          tabBarLabelStyle: { fontFamily: Fonts.sansSemi, fontSize: 11, letterSpacing: 0.1 },
        }}>
        <Tabs.Screen
          name="folgesvend"
          options={{ title: 'Følgesvend', tabBarIcon: icon('arrow-back-circle-outline') }}
          listeners={{ tabPress: (e) => { e.preventDefault(); router.navigate('/(tabs)'); } }}
        />
        <Tabs.Screen name="index" options={{ title: 'Oversigt', tabBarIcon: icon('grid-outline') }} />
        <Tabs.Screen name="entiteter" options={{ title: 'Entiteter', tabBarIcon: icon('list-outline') }} />
        <Tabs.Screen
          name="tilfoej"
          options={{ title: 'Tilføj', tabBarIcon: icon('add-circle-outline') }}
          listeners={{ tabPress: (e) => { e.preventDefault(); setOpretOpen(true); } }}
        />
        <Tabs.Screen name="konto" options={{ title: 'Konto', tabBarIcon: icon('person-circle-outline') }} />
      </Tabs>
      <OpretSheet visible={opretOpen} onClose={() => setOpretOpen(false)} />
    </>
  );
}

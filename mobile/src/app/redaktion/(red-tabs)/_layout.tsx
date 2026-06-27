// Redaktions-tabbar: Oversigt · Entiteter · Tilføj · Konto (IKKE publikums-fanerne, spec §2).
// "Tilføj" navigerer ikke — den åbner opret-sheet (plan 2-stub). Vi intercepter tabPress.
import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import { useState } from 'react';
import type { ColorValue } from 'react-native';
import { Border, Colors, Fonts } from '../../../theme/tokens';

type IconName = keyof typeof Ionicons.glyphMap;
const icon = (name: IconName) => ({ color, size }: { color: ColorValue; size: number }) =>
  <Ionicons name={name} color={color as string} size={size} />;

export default function RedTabsLayout() {
  const [, setOpretOpen] = useState(false); // plan 1: stub; sheet-komponent = plan 2
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: Colors.bordeaux,
        tabBarInactiveTintColor: Colors.textMuted2,
        tabBarStyle: { height: 66, paddingTop: 8, paddingBottom: 10,
          backgroundColor: Colors.ink, borderTopColor: Border.medium },
        tabBarLabelStyle: { fontFamily: Fonts.sansSemi, fontSize: 11, letterSpacing: 0.1 },
      }}>
      <Tabs.Screen name="index" options={{ title: 'Oversigt', tabBarIcon: icon('grid-outline') }} />
      <Tabs.Screen name="entiteter" options={{ title: 'Entiteter', tabBarIcon: icon('list-outline') }} />
      <Tabs.Screen
        name="tilfoej"
        options={{ title: 'Tilføj', tabBarIcon: icon('add-circle-outline') }}
        listeners={{ tabPress: (e) => { e.preventDefault(); setOpretOpen(true); } }}
      />
      <Tabs.Screen name="konto" options={{ title: 'Konto', tabBarIcon: icon('person-circle-outline') }} />
    </Tabs>
  );
}

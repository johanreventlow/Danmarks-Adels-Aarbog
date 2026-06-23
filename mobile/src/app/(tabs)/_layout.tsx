// Bund-tabbar — README §4: 4 faner Hjem · Stamtræ · Slægtskab · Søg, bordeaux aktiv.
import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import type { ColorValue } from 'react-native';
import { Border, Colors, Fonts } from '../../theme/tokens';

type IconName = keyof typeof Ionicons.glyphMap;

function tabIcon(name: IconName) {
  return ({ color, size }: { color: ColorValue; size: number }) => (
    <Ionicons name={name} color={color as string} size={size} />
  );
}

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: Colors.bordeaux,
        tabBarInactiveTintColor: Colors.textMuted2,
        tabBarStyle: {
          height: 66,
          paddingTop: 8,
          paddingBottom: 10,
          backgroundColor: Colors.paperCard,
          borderTopColor: Border.medium,
        },
        tabBarLabelStyle: {
          fontFamily: Fonts.sansMedium,
          fontSize: 11,
        },
      }}>
      <Tabs.Screen
        name="index"
        options={{ title: 'Hjem', tabBarIcon: tabIcon('home-outline') }}
      />
      <Tabs.Screen
        name="tree"
        options={{ title: 'Stamtræ', tabBarIcon: tabIcon('git-network-outline') }}
      />
      <Tabs.Screen
        name="relate"
        options={{ title: 'Slægtskab', tabBarIcon: tabIcon('people-outline') }}
      />
      <Tabs.Screen
        name="search"
        options={{ title: 'Søg', tabBarIcon: tabIcon('search-outline') }}
      />
    </Tabs>
  );
}

import { View } from 'react-native';
import { TopBar } from './TopBar';
import { Body } from './Typography';
import { Colors } from '../theme/tokens';

// Fuld-skærm centreret besked (henter/fejl/ikke-fundet) — delt af redaktions-skærmene der
// tidligere hver havde deres egen kopi (person-editor, entitetsliste, objekt-materiale).
export function CenterMsg({ title, children }: { title: string; children: string }) {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={title} />
      <Body color={Colors.textMuted} style={{ padding: 24 }}>{children}</Body>
    </View>
  );
}

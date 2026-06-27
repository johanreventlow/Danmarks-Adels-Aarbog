// Stub (plan 2): entitetslister. Plan 1 viser tom-tilstand.
import { View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body } from '../../../components/Typography';
import { Colors } from '../../../theme/tokens';
export default function Entiteter() {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Entiteter" showBack={false} />
      <View style={{ padding: 24 }}>
        <Body color={Colors.textMuted}>Entitetslister kommer i næste version.</Body>
      </View>
    </View>
  );
}

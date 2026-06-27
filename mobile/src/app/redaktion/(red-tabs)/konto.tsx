// Midlertidig placeholder (plan 2: konto/auth). Plan 1 viser tom-tilstand.
import { View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body } from '../../../components/Typography';
import { Colors } from '../../../theme/tokens';
export default function Konto() {
  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title="Konto" showBack={false} />
      <View style={{ padding: 24 }}>
        <Body color={Colors.textMuted}>Konto-funktioner kommer i næste version.</Body>
      </View>
    </View>
  );
}

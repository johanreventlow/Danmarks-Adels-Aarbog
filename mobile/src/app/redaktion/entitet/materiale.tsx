// Objekt-foto (mediehåndtering Slice 0h): minimal materiale-skærm for entiteter uden nogen
// detail-editor endnu (gods/våben). Bevidst IKKE en fuld editor — kun galleri + upload/fjern/slet
// via den delte MaterialeSektion (samme komponent som entitet/slaegt-narrativ.tsx bruger).
import { useLocalSearchParams } from 'expo-router';
import { ScrollView, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { CenterMsg } from '../../../components/CenterMsg';
import { Mono, Serif } from '../../../components/Typography';
import { MaterialeSektion } from '../../../components/redaktion/MaterialeSektion';
import { useStore } from '../../../store/useStore';
import { Colors } from '../../../theme/tokens';

// UI-entitetsnøgle (matcher entitet/[type].tsx) → objekt_type i basen (matcher tabelnavnet, jf.
// red_upload_media/red_relation's polymorfe objekt_type-konvention: 'estate', 'organisation', ...).
const OBJEKT_TYPE: Record<string, string> = { gods: 'estate', vaaben: 'coat_of_arms' };

export default function ObjektMateriale() {
  const { type, id, navn } = useLocalSearchParams<{ type: string; id: string; navn?: string }>();
  const rolle = useStore((s) => s.rolle);
  const objektType = OBJEKT_TYPE[type ?? ''];
  const titel = navn ?? '(uden navn)';

  if (!objektType) return <CenterMsg title="Materiale">Ukendt entitetstype.</CenterMsg>;
  if (rolle !== 'redaktion') return <CenterMsg title={titel}>Kræver redaktør-rolle.</CenterMsg>;

  return (
    <View style={{ flex: 1, backgroundColor: Colors.paperBg }}>
      <TopBar title={titel} />
      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <Serif size={20} style={{ marginBottom: 4 }}>{titel}</Serif>
        <Mono size={10} color={Colors.textMuted} style={{ marginBottom: 14 }}>Materiale</Mono>
        <MaterialeSektion objektType={objektType} objektId={id!} />
      </ScrollView>
    </View>
  );
}

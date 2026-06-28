import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { TopBar } from '../../../components/TopBar';
import { Body, Serif } from '../../../components/Typography';
import { useStore } from '../../../store/useStore';
import { Border, Colors } from '../../../theme/tokens';

export default function Entiteter() {
  const router = useRouter();
  const rolle = useStore((s) => s.rolle);
  const status = useStore((s) => s.redaktionStatus);
  const model = useStore((s) => s.redaktionModel);
  const aux = useStore((s) => s.redaktionAux);

  if (rolle !== 'redaktion')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Kræver redaktør-rolle.</Body></View>;
  if (status === 'error')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Kunne ikke hente redaktion-data.</Body></View>;
  if (status !== 'ready')
    return <View style={s.wrap}><TopBar title="Entiteter" showBack={false} /><Body color={Colors.textMuted} style={{ padding: 24 }}>Henter…</Body></View>;

  const celler = [
    { n: model?.persons.length ?? 0, label: 'Personer', rute: '/redaktion/entitet/person' },
    { n: aux?.godsListe.length ?? 0, label: 'Godser', rute: '/redaktion/entitet/gods' },
    { n: aux?.kildeListe.length ?? 0, label: 'Kilder', rute: '/redaktion/entitet/kilde' },
    { n: aux?.orgListe.length ?? 0, label: 'Organisationer', rute: '/redaktion/entitet/organisation' },
    { n: aux?.medieListe.length ?? 0, label: 'Medier', rute: '/redaktion/entitet/medie' },
    { n: aux?.vaabenListe.length ?? 0, label: 'Våben', rute: '/redaktion/entitet/vaaben' },
  ];

  return (
    <View style={s.wrap}>
      <TopBar title="Entiteter" showBack={false} />
      <ScrollView contentContainerStyle={{ padding: 18 }}>
        <View style={s.grid}>
          {celler.map((c) => (
            <Pressable key={c.label} style={s.cell} onPress={() => router.navigate(c.rute as never)}>
              <Serif size={21} color={Colors.bordeaux}>{c.n}</Serif>
              <Body size={13}>{c.label}</Body>
            </Pressable>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: Colors.paperBg },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 9 },
  cell: { backgroundColor: Colors.paperCard, borderWidth: 1, borderColor: Border.light,
    borderRadius: 13, padding: 14, minWidth: '47%' },
});

// daaRise — forside-elementer rejser sig sekventielt (README §6: translateY(13px)→0, .62s,
// delays .04/.10/.16/.22/.28). Wrapper der animerer sit barn ved mount.
import { useEffect } from 'react';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withTiming,
} from 'react-native-reanimated';
import { Motion } from '../theme/tokens';

export function Rise({
  index = 0,
  children,
  style,
}: {
  index?: number;
  children: React.ReactNode;
  style?: object;
}) {
  const p = useSharedValue(0);
  useEffect(() => {
    const delay = Motion.riseDelays[Math.min(index, Motion.riseDelays.length - 1)];
    p.value = withDelay(delay, withTiming(1, { duration: Motion.riseDuration }));
  }, [index, p]);

  const anim = useAnimatedStyle(() => ({
    opacity: p.value,
    transform: [{ translateY: (1 - p.value) * Motion.riseTranslate }],
  }));

  return <Animated.View style={[style, anim]}>{children}</Animated.View>;
}

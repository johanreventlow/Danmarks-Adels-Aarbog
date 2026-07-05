// Delt bogmærke-ribbon-ikon (SVG). Én kilde til glyfen — brugt i feed-kort + top-bar.
// (CLAUDE.md: web itererede allerede på denne form ⚑→ribbon; hold den ét sted.)
import Svg, { Path } from 'react-native-svg';
import { Colors } from '../theme/tokens';

const D = 'M3 2.2h11a1 1 0 0 1 1 1V16.4a.6.6 0 0 1-.94.5L8.5 13.4l-4.56 3.5A.6.6 0 0 1 3 16.4V3.2a1 1 0 0 1 1-1Z';

// filled = gemt (fyldt bordeaux). light = lys stroke til mørke kort (citat).
export function BookmarkIcon({
  filled = false,
  light = false,
  width = 15,
  height = 17,
}: {
  filled?: boolean;
  light?: boolean;
  width?: number;
  height?: number;
}) {
  return (
    <Svg width={width} height={height} viewBox="0 0 17 19">
      <Path
        d={D}
        fill={filled ? Colors.bordeaux : 'none'}
        stroke={filled ? Colors.bordeaux : light ? '#cabfa9' : '#7a7060'}
        strokeWidth={1.3}
      />
    </Svg>
  );
}

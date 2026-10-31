import type { MatchFrame } from '@daa/core';
import type { RankOptions } from '../rank';

const f = (id: string | number, nameKey: string, birth: number | null = null, sex: MatchFrame['sex'] = 'ukendt',
           death: number | null = null): MatchFrame => ({
  id, nameKey, birthMin: birth, birthMax: birth, deathMin: death, deathMax: death, sex,
});
const origins = new Map([['p1', { name: 'accepted_interpretation', birth: 'accepted_interpretation', death: null }],
                         ['p2', { name: 'accepted_interpretation', birth: null, death: null }]]);

// Syntetiske scenarier; de forventede literaler i golden-testen er genereret fra 1.1-koden (15061332).
export const SCENARIOS: Record<string, { personas: MatchFrame[]; persons: MatchFrame[]; opts: RankOptions }> = {
  enkeltperson: {
    personas: [f('p1', 'ludvig reventlow', 1848)],
    persons: [f(7, 'ludvig reventlowe', 1848), f(8, 'ludvig reventlow', 1790)],
    opts: { topK: 3, origins },
  },
  klynge: {
    personas: [f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
    persons: [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(8, 'ludvig reventlow', null, 'mand'), f(9, 'anna reventlow')],
    opts: { topK: 3, origins, clusters: new Map([[7, 7], [8, 7]]) },
  },
  familie_repraesentant_ombytning: {
    personas: [f('p1', 'ludvig reventlow', 1848, 'ukendt', 1900)],
    persons: [f(7, 'ludvig reventlow', 1848, 'mand', 1900), f(9, 'ludvig reventlow', null, 'mand'), f(11, 'ludvig reventlau', 1848)],
    opts: {
      topK: 3, origins, clusters: new Map([[7, 7], [9, 7]]), familyNameMin: 0.9,
      families: new Map([['p1', { principal_person_id: 100, marriage_ordinal: 1, marriage_claims_in_post: 1,
        families: [{ family_id: 1, ordinal: 1, konfidens: ['sikker'], partners: [9] }] }]]),
    },
  },
  topk_afskaering: {
    personas: [f('p1', 'anna reventlow', 1850), f('p2', 'anna reventlow')],
    persons: [f(1, 'anna reventlow', 1850), f(2, 'anna reventlau', 1850), f(3, 'anna reventlowx'), f(4, 'anna reventlowxx')],
    opts: { topK: 2, origins },
  },
};

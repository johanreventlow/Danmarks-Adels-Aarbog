import { describe, expect, it } from 'vitest';
import { initialsOf } from '../pool';

describe('initialsOf', () => {
  it('tager første bogstav', () => expect(initialsOf('Iwan Reventlow')).toBe('I'));
  it('springer parenteser over', () => expect(initialsOf('(Søn)')).toBe('S'));
  it('bevarer æ, ø og å', () => expect(initialsOf('øllegaard')).toBe('Ø'));
  it('navn uden bogstaver giver ?', () => expect(initialsOf('(—)')).toBe('?'));
});

// Jest til kritiske-path-tests (rene TS-moduler: collation, buildModel, buildAux, selektorer).
// Node-miljø — modulerne importerer ikke RN-runtime, kun typer + ren logik.
module.exports = {
  preset: 'jest-expo',
  testEnvironment: 'node',
  testMatch: ['**/__tests__/**/*.test.ts'],
};

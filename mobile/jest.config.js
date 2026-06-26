// Jest til kritiske-path-tests (rene TS-moduler: collation, buildModel, buildAux, selektorer).
// Node-miljø — modulerne importerer ikke RN-runtime, kun typer + ren logik.
// moduleNameMapper mocker native-afhængigheder som AsyncStorage og URL-polyfill, så auth.ts
// kan importeres i node-miljø uden RN-runtime (kun mapProfileRow testes her).
module.exports = {
  preset: 'jest-expo',
  testEnvironment: 'node',
  testMatch: ['**/__tests__/**/*.test.ts'],
  moduleNameMapper: {
    '^@react-native-async-storage/async-storage$':
      '<rootDir>/node_modules/@react-native-async-storage/async-storage/jest/async-storage-mock.js',
    '^react-native-url-polyfill/auto$': '<rootDir>/__mocks__/react-native-url-polyfill-auto.js',
  },
};

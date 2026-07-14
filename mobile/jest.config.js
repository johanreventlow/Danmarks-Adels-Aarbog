// Jest til kritiske-path-tests (rene TS-moduler: collation, buildModel, buildAux, selektorer).
// Node-miljø — modulerne importerer ikke RN-runtime, kun typer + ren logik.
// moduleNameMapper mocker native-afhængigheder som AsyncStorage og URL-polyfill, så auth.ts
// kan importeres i node-miljø uden RN-runtime (kun mapProfileRow testes her).
module.exports = {
  preset: 'jest-expo',
  testEnvironment: 'node',
  testMatch: ['**/__tests__/**/*.test.ts'],
  moduleNameMapper: {
    // require.resolve i stedet for <rootDir>/node_modules/... — npm-workspace-installet
    // (spike-task 1: rod-package.json workspaces) hoister pakken til rod-node_modules, ikke
    // mobile/node_modules, så en hardkodet <rootDir>-sti brækker. require.resolve følger
    // Nodes egen opad-gående modul-søgning og finder pakken uanset hoisting-niveau.
    '^@react-native-async-storage/async-storage$': require.resolve(
      '@react-native-async-storage/async-storage/jest/async-storage-mock.js',
    ),
    '^react-native-url-polyfill/auto$': '<rootDir>/__mocks__/react-native-url-polyfill-auto.js',
  },
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@expo-google-fonts/.*|react-navigation|@react-navigation/.*|@unimodules/.*|unimodules|sentry-expo|native-base|react-native-svg|@daa/.*))',
  ],
};

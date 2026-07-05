import { vi } from 'vitest';

// maplibre-gl's top-level module code kalder window.URL.createObjectURL(...) ubetinget
// (Worker-bootstrapping) — jsdom implementerer ikke createObjectURL, så et almindeligt import
// af pakken crasher enhver test der transitivt importerer en fil med GeoMap.tsx. Mockes globalt;
// ingen test har brug for ægte WebGL-rendering (jsdom har ingen alligevel).
vi.mock('maplibre-gl', () => {
  class FakeMap {
    on() {}
    once() {}
    off() {}
    addSource() {}
    addLayer() {}
    addControl() {}
    removeControl() {}
    getSource() {
      return { setData() {}, getClusterExpansionZoom: () => Promise.resolve(0) };
    }
    getCanvas() {
      return { style: {} };
    }
    isStyleLoaded() {
      return false;
    }
    easeTo() {}
    fitBounds() {}
    remove() {}
    scrollZoom = { disable() {} };
    dragPan = { disable() {} };
    dragRotate = { disable() {} };
    doubleClickZoom = { disable() {} };
    touchZoomRotate = { disable() {} };
  }
  class FakeNavigationControl {}
  return { default: { Map: FakeMap, NavigationControl: FakeNavigationControl } };
});

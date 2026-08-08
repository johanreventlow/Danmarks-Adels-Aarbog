(function (global) {
  'use strict';

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function hasOwn(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
  }

  function dictionary(entries) {
    return entries.reduce((result, [key, value]) => {
      result[key] = value;
      return result;
    }, Object.create(null));
  }

  function sameValue(left, right) {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  function element(tag, text, attributes) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    Object.entries(attributes || {}).forEach(([name, value]) => {
      node.setAttribute(name, value);
    });
    return node;
  }

  function actionButton(text, action, data) {
    const button = element('button', text, { type: 'button', 'data-action': action });
    Object.entries(data || {}).forEach(([name, value]) => {
      button.setAttribute(`data-${name.replace(/[A-Z]/g, m => '-' + m.toLowerCase())}`, value);
    });
    return button;
  }

  function downloadJson(value, filename) {
    const blob = new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
  }

  function readStoredDraft(storage, key) {
    try {
      const raw = storage.getItem(key);
      return raw ? JSON.parse(raw) : null;
    } catch (error) {
      return null;
    }
  }

  function writeStoredDraft(storage, key, value) {
    try {
      storage.setItem(key, JSON.stringify(value));
      return '';
    } catch (error) {
      return 'Kladden kunne ikke gemmes lokalt i denne browser.';
    }
  }

  global.DAAReviewShared = {
    element, actionButton, clone, hasOwn, dictionary, sameValue,
    downloadJson, readStoredDraft, writeStoredDraft,
  };
}(typeof globalThis === 'undefined' ? this : globalThis));

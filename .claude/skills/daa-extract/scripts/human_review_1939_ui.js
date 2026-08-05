(function (global) {
  'use strict';

  const OUTCOMES = new Set([
    'human_selected_candidate', 'no_candidate_fits', 'possible_duplicate', 'undecidable',
  ]);
  const REVIEW_SCHEMA_VERSION = 1;
  const SOURCE_FIELDS = [
    'edition', 'baseline_sha256', 'calamari_sha256', 'raw_ocr_sha256', 'pdf_sha256',
    'profile_version',
  ];
  const ACCEPTED_EVIDENCE_FIELDS = [
    'candidate_id', 'post_index', 'calamari_span', 'calamari_verbatim_text', 'pdf_pages',
    'kind', 'raw_char_from', 'raw_char_to', 'raw_verbatim_text', 'raw_excerpt_sha256',
  ];

  function sourceIdentity(source) {
    function canonical(value) {
      if (Array.isArray(value)) return value.map(canonical);
      if (value && typeof value === 'object') return Object.keys(value).sort().reduce((result, key) => {
        result[key] = canonical(value[key]);
        return result;
      }, {});
      return value;
    }
    return JSON.stringify(canonical(source || {}));
  }

  function storageKeyFor(data) {
    return `daa1939-review:v${REVIEW_SCHEMA_VERSION}:${sourceIdentity(data.source || {})}`;
  }

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function hasOwn(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
  }

  function decisionMap(value) {
    if (Array.isArray(value)) {
      const result = {};
      value.forEach(entry => {
        if (!entry || typeof entry !== 'object' || typeof entry.baseline_record_key !== 'string'
          || hasOwn(result, entry.baseline_record_key)) throw new Error('Ugyldig kladdepost');
        result[entry.baseline_record_key] = entry;
      });
      return result;
    }
    if (!value || typeof value !== 'object') throw new Error('Ugyldig kladde');
    return value;
  }

  function candidatesContain(record, candidateId) {
    return typeof candidateId === 'string' && Array.isArray(record.candidates)
      && record.candidates.some(candidate => candidate.candidate_id === candidateId);
  }

  function claimCandidate(owners, candidateId, recordKey) {
    const owner = owners.get(candidateId);
    if (owner && owner !== recordKey) throw new Error('Kandidaten er allerede valgt for en anden historisk post');
    owners.set(candidateId, recordKey);
  }

  function autoCandidateOwners(recordByKey) {
    const owners = new Map();
    recordByKey.forEach((record, recordKey) => {
      const candidateId = record.classification && record.classification.candidate
        && record.classification.candidate.candidate_id;
      if (candidateId !== undefined) {
        if (typeof candidateId !== 'string' || !candidateId) throw new Error('Ugyldig automatisk kandidat');
        claimCandidate(owners, candidateId, recordKey);
      }
    });
    return owners;
  }

  function validateLegacyDecision(decision, record, recordKey, recordByKey, owners, hasOutcome) {
    const status = decision.review_status;
    if (status === undefined) return;
    if (!['unreviewed', 'accepteret', 'eksplicit_dublet', 'menneskeark'].includes(status)) {
      throw new Error('Ukendt review_status');
    }
    if (status === 'unreviewed') {
      if (!hasOutcome && (hasOwn(decision, 'candidate_id') || hasOwn(decision, 'duplicate_of_baseline_record_key')
        || hasOwn(decision, 'reason'))) throw new Error('Ugyldig ugennemgået post');
      return;
    }
    if (status === 'accepteret') {
      if (hasOutcome || ACCEPTED_EVIDENCE_FIELDS.some(field => !hasOwn(decision, field))
        || !candidatesContain(record, decision.candidate_id)
        || typeof decision.raw_excerpt_sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(decision.raw_excerpt_sha256)) {
        throw new Error('Ugyldig accepteret post');
      }
      claimCandidate(owners, decision.candidate_id, recordKey);
      return;
    }
    if (status === 'eksplicit_dublet') {
      if (hasOutcome || typeof decision.duplicate_of_baseline_record_key !== 'string'
        || decision.duplicate_of_baseline_record_key === recordKey
        || !recordByKey.has(decision.duplicate_of_baseline_record_key)
        || hasOwn(decision, 'candidate_id') || hasOwn(decision, 'reason')) {
        throw new Error('Ugyldig dubletpost');
      }
      return;
    }
    if (typeof decision.reason !== 'string' || !decision.reason.trim()) {
      throw new Error('Ugyldig menneskearkpost');
    }
    if (!hasOutcome && (hasOwn(decision, 'candidate_id') || hasOwn(decision, 'duplicate_of_baseline_record_key'))) {
      throw new Error('Ugyldig menneskearkpost');
    }
  }

  function validateDecisionState(value, recordByKey) {
    const decisions = decisionMap(value);
    const result = {};
    const candidateOwners = autoCandidateOwners(recordByKey);
    Object.entries(decisions).forEach(([recordKey, decision]) => {
      const record = recordByKey.get(recordKey);
      if (!record || !decision || typeof decision !== 'object'
        || decision.baseline_record_key !== recordKey) throw new Error('Ugyldig kladdepost');
      const hasOutcome = hasOwn(decision, 'outcome');
      const hasCandidate = hasOwn(decision, 'candidate_id');
      const hasDuplicate = hasOwn(decision, 'duplicate_of_baseline_record_key');
      validateLegacyDecision(decision, record, recordKey, recordByKey, candidateOwners, hasOutcome);
      if (!hasOutcome) {
        if (decision.review_status === undefined && (hasCandidate || hasDuplicate)) {
          throw new Error('Ugyldigt valg uden udfald');
        }
        result[recordKey] = clone(decision);
        return;
      }
      if (!OUTCOMES.has(decision.outcome)) throw new Error('Ukendt udfald');
      if (decision.outcome === 'human_selected_candidate') {
        if (!candidatesContain(record, decision.candidate_id) || hasDuplicate) {
          throw new Error('Ugyldigt kandidatvalg');
        }
        claimCandidate(candidateOwners, decision.candidate_id, recordKey);
      } else if (decision.outcome === 'possible_duplicate') {
        if (hasCandidate || typeof decision.duplicate_of_baseline_record_key !== 'string'
          || decision.duplicate_of_baseline_record_key === recordKey
          || !recordByKey.has(decision.duplicate_of_baseline_record_key)) {
          throw new Error('Ugyldigt dubletvalg');
        }
      } else if (hasCandidate || hasDuplicate) {
        throw new Error('Ugyldigt udvalg for dette udfald');
      }
      result[recordKey] = clone(decision);
    });
    return result;
  }

  function blockRecovery(state, message) {
    state.recoveryBlocked = true;
    state.decisions = {};
    state.storageError = message;
  }

  function sameValue(left, right) {
    return sourceIdentity({ value: left }) === sourceIdentity({ value: right });
  }

  function overlayCachedDecisions(modelDecisions, restored) {
    const browserFields = new Set([
      'baseline_record_key', 'outcome', 'candidate_id', 'duplicate_of_baseline_record_key',
      'decided_at', 'draft', 'reason',
    ]);
    const result = clone(modelDecisions);
    Object.entries(restored).forEach(([recordKey, cached]) => {
      const model = result[recordKey] || { baseline_record_key: recordKey };
      Object.entries(cached).forEach(([field, value]) => {
        if (field !== 'baseline_record_key' && hasOwn(model, field) && !sameValue(model[field], value)) {
          throw new Error('Cachemetadata matcher ikke den aktuelle kilde');
        }
        if (browserFields.has(field)) return;
        if (!hasOwn(model, field) || !sameValue(model[field], value)) {
          throw new Error('Cachemetadata matcher ikke den aktuelle kilde');
        }
      });
      result[recordKey] = {
        ...model,
        ...Object.fromEntries(Object.entries(cached).filter(([field]) => browserFields.has(field))),
      };
    });
    return result;
  }

  function restoreOrInitialize(data, storage, now) {
    const records = Array.isArray(data.records) ? data.records : [];
    const recordByKey = new Map(records.map(record => [record.record_key, record]));
    const state = {
      data,
      records,
      recordByKey,
      decisions: {},
      selectedKey: records[0] && records[0].record_key,
      activeView: data.default_view || 'required',
      expandedCandidates: {},
      duplicateSearch: '',
      undoStack: [],
      storageKey: storageKeyFor(data),
      storage,
      now,
      message: 'Klar. Ændringer gemmes automatisk lokalt.',
      error: '',
      storageError: '',
      recoveryBlocked: false,
    };
    const modelDecisions = Object.fromEntries(records
      .filter(record => record.decision != null)
      .map(record => [record.record_key, record.decision]));
    try {
      state.decisions = validateDecisionState(modelDecisions, recordByKey);
    } catch (_) {
      blockRecovery(state, 'Kildens beslutninger kan ikke bruges sikkert.');
      return state;
    }
    let saved;
    try {
      saved = storage.getItem(state.storageKey);
    } catch (_) {
      blockRecovery(state, 'Den lokale kladde kan ikke læses sikkert.');
      return state;
    }
    if (saved === null) return state;
    if (typeof saved !== 'string' || !saved) {
      blockRecovery(state, 'Den lokale kladde kan ikke bruges sikkert.');
      return state;
    }
    try {
      const parsed = JSON.parse(saved);
      if (!parsed || parsed.schema_version !== REVIEW_SCHEMA_VERSION
        || sourceIdentity(parsed.source || {}) !== sourceIdentity(data.source || {})) {
        blockRecovery(state, 'Den lokale kladde kan ikke bruges til denne kilde eller version.');
        return state;
      }
      const restored = decisionMap(Array.isArray(parsed.entries) ? parsed.entries : parsed.decisions);
      state.decisions = validateDecisionState(
        overlayCachedDecisions(state.decisions, restored), recordByKey,
      );
    } catch (_) {
      blockRecovery(state, 'Den lokale kladde kan ikke bruges sikkert.');
    }
    return state;
  }

  function completed(state, recordKey) {
    const decision = state.decisions[recordKey];
    return Boolean(decision && (decision.outcome || decision.review_status !== 'unreviewed'));
  }

  function keysForView(state, view) {
    if (view === 'completed') return state.records
      .filter(record => completed(state, record.record_key))
      .map(record => record.record_key);
    const configured = (state.data.views && state.data.views[view]) || [];
    return configured.filter(key => state.recordByKey.has(key));
  }

  function visibleKeys(state) {
    return keysForView(state, state.activeView);
  }

  function normalizeSelection(state) {
    const keys = visibleKeys(state);
    if (!keys.includes(state.selectedKey)) state.selectedKey = keys[0];
  }

  function persist(state) {
    if (state.recoveryBlocked) throw new Error('Gendannelse er blokeret');
    state.storage.setItem(state.storageKey, JSON.stringify({
      schema_version: REVIEW_SCHEMA_VERSION,
      source: state.data.source,
      decisions: state.decisions,
    }));
  }

  function showSaved(state, message) {
    state.error = '';
    state.message = message;
  }

  function showStorageError(state) {
    state.storageError = 'Kunne ikke gemme lokalt. Dit valg er ikke bekræftet eller flyttet frem.';
  }

  function validateUiChoice(state, outcome, payload) {
    const record = state.recordByKey.get(state.selectedKey);
    if (!record || !OUTCOMES.has(outcome)) throw new Error('Ugyldigt valg');
    const existing = state.decisions[record.record_key];
    if (existing && ['accepteret', 'eksplicit_dublet'].includes(existing.review_status)) {
      throw new Error('Endelige legacy-afgørelser kan ikke ændres her');
    }
    const decision = clone(state.decisions[record.record_key] || {
      baseline_record_key: record.record_key,
    });
    delete decision.outcome;
    delete decision.candidate_id;
    delete decision.duplicate_of_baseline_record_key;
    delete decision.decided_at;
    delete decision.draft;
    decision.outcome = outcome;
    decision.decided_at = state.now();
    if (outcome === 'human_selected_candidate') {
      const candidateId = payload.candidate_id;
      if (hasOwn(payload, 'duplicate_of_baseline_record_key')
        || !record.candidates.some(candidate => candidate.candidate_id === candidateId)) {
        throw new Error('Kandidaten findes ikke på denne post');
      }
      if (Object.entries(state.decisions).some(([recordKey, choice]) => recordKey !== record.record_key
          && choice && choice.candidate_id === candidateId)) {
        throw new Error('Kandidaten er allerede valgt for en anden historisk post');
      }
      const autoOwner = autoCandidateOwners(state.recordByKey).get(candidateId);
      if (autoOwner && autoOwner !== record.record_key) {
        throw new Error('Kandidaten er allerede valgt for en anden historisk post');
      }
      decision.candidate_id = candidateId;
    }
    if (outcome === 'possible_duplicate') {
      const target = payload.duplicate_of_baseline_record_key;
      if (hasOwn(payload, 'candidate_id') || !state.recordByKey.has(target)
        || target === record.record_key) {
        throw new Error('Vælg en anden kendt historisk post som dubletmål');
      }
      decision.duplicate_of_baseline_record_key = target;
    }
    if ((outcome === 'no_candidate_fits' || outcome === 'undecidable')
      && (hasOwn(payload, 'candidate_id') || hasOwn(payload, 'duplicate_of_baseline_record_key'))) {
      throw new Error('Ugyldigt udvalg for dette udfald');
    }
    if (typeof payload.reason === 'string' && payload.reason.trim()) {
      decision.reason = payload.reason.trim();
    }
    return decision;
  }

  function restoreDecision(state, recordKey, decision) {
    if (decision) state.decisions[recordKey] = decision;
    else delete state.decisions[recordKey];
  }

  function moveToNextVisible(state) {
    const keys = visibleKeys(state);
    const position = keys.indexOf(state.selectedKey);
    const next = keys.slice(position + 1).find(key => !completed(state, key));
    if (next) state.selectedKey = next;
  }

  function choose(state, outcome, payload) {
    if (state.recoveryBlocked) return false;
    const recordKey = state.selectedKey;
    const previous = clone(state.decisions[recordKey] || null);
    const navigation = { activeView: state.activeView, selectedKey: state.selectedKey };
    let decision;
    try {
      decision = validateUiChoice(state, outcome, payload || {});
    } catch (error) {
      state.error = error.message;
      render(state);
      return false;
    }
    state.decisions[recordKey] = decision;
    try {
      persist(state);
    } catch (_) {
      restoreDecision(state, recordKey, previous);
      showStorageError(state);
      render(state);
      return false;
    }
    state.undoStack.push({ recordKey, previous, navigation });
    showSaved(state, '✓ Visuelt spor er gemt lokalt.');
    moveToNextVisible(state);
    render(state);
    return true;
  }

  function undo(state) {
    if (state.recoveryBlocked) return false;
    const item = state.undoStack.pop();
    if (!item) return false;
    const current = clone(state.decisions[item.recordKey] || null);
    restoreDecision(state, item.recordKey, clone(item.previous));
    try {
      persist(state);
    } catch (_) {
      restoreDecision(state, item.recordKey, current);
      state.undoStack.push(item);
      showStorageError(state);
      render(state);
      return false;
    }
    state.selectedKey = item.navigation.selectedKey;
    state.activeView = item.navigation.activeView;
    showSaved(state, '✓ Fortrydelsen er gemt lokalt.');
    render(state);
    return true;
  }

  function selectRecord(state, recordKey) {
    if (!state.recordByKey.has(recordKey)) return false;
    state.selectedKey = recordKey;
    render(state);
    return true;
  }

  function setView(state, view) {
    if (!['required', 'automatic', 'audit', 'completed'].includes(view)) return false;
    state.activeView = view;
    normalizeSelection(state);
    render(state);
    return true;
  }

  function navigate(state, direction) {
    const keys = visibleKeys(state);
    const position = keys.indexOf(state.selectedKey);
    const nextPosition = position + direction;
    if (position < 0 || nextPosition < 0 || nextPosition >= keys.length) return false;
    state.selectedKey = keys[nextPosition];
    render(state);
    return true;
  }

  function element(tag, text, attributes) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    Object.entries(attributes || {}).forEach(([name, value]) => {
      if (value !== undefined && value !== null) node.setAttribute(name, String(value));
    });
    return node;
  }

  function actionButton(text, action, data) {
    const button = element('button', text, { type: 'button', 'data-action': action });
    Object.entries(data || {}).forEach(([key, value]) => { button.dataset[key] = String(value); });
    return button;
  }

  function renderDashboard(state, root) {
    const dashboard = element('section', undefined, { 'data-role': 'dashboard' });
    const names = { required: 'Kræver menneskeark', automatic: 'Automatiske', audit: 'Kontrolprøve', completed: 'Afsluttede' };
    ['required', 'automatic', 'audit', 'completed'].forEach(view => {
      const count = keysForView(state, view).length;
      const button = actionButton(`${names[view]} (${count})`, 'set-view', { view });
      if (view === state.activeView) button.setAttribute('aria-current', 'true');
      dashboard.append(button);
    });
    dashboard.append(actionButton('Eksportér kladde', 'export-draft'));
    root.append(dashboard);
  }

  function renderList(state, root) {
    const list = element('nav', undefined, { 'data-role': 'record-list', 'aria-label': 'Poster' });
    visibleKeys(state).forEach(recordKey => {
      const record = state.recordByKey.get(recordKey);
      const button = actionButton(record.navn || '(uden navn)', 'select-record', { recordKey });
      if (recordKey === state.selectedKey) button.setAttribute('aria-current', 'true');
      list.append(button);
    });
    root.append(list);
  }

  function renderCandidate(state, record, candidate, index) {
    const allVisible = state.expandedCandidates[record.record_key];
    if (!allVisible && index >= 3) return null;
    const details = element('details', undefined, { class: 'candidate' });
    if (record.initial_candidate_ids.includes(candidate.candidate_id)) details.open = true;
    details.append(element('summary', `Parserpost ${candidate.lokal_id || '(uden lokalt id)'}`));
    details.append(element('p', `PDF s. ${(candidate.pdf_pages || []).join('-')} · Calamari-scan ${(candidate.calamari_pages || []).join('-')}`));
    details.append(element('p', 'Boksens start og slut er parserens foreslåede postgrænse.'));
    details.append(element('pre', candidate.raw_text || ''));
    const button = actionButton('Vælg denne kandidat', 'select-candidate', { candidateId: candidate.candidate_id });
    const decision = state.decisions[record.record_key];
    if (decision && decision.candidate_id === candidate.candidate_id) button.setAttribute('aria-pressed', 'true');
    details.append(button);
    return details;
  }

  function renderRecord(state, root) {
    const record = state.recordByKey.get(state.selectedKey);
    if (!record) {
      root.append(element('p', 'Der er ingen poster i denne visning.'));
      return;
    }
    root.append(element('h1', record.navn || '(uden navn)'));
    root.append(element('p', `PDF-sider: ${record.sider || 'ukendt'} · Klasse: ${record.queue_class} · Årsag: ${record.reason_da || record.reason_code || 'ukendt'}`));
    if (record.is_audit) root.append(element('p', 'Kontrolprøve: denne automatiske afgørelse skal også læses af et menneske.', { 'data-role': 'audit-label' }));
    root.append(element('h2', 'Gammel kildetekst'));
    root.append(element('pre', record.narrative || ''));
    root.append(element('h2', 'Ny OCR: kandidatposter'));
    const candidates = Array.isArray(record.candidates) ? record.candidates : [];
    if (!candidates.length) root.append(element('p', 'Ingen parserkandidat på samme PDF-side.'));
    candidates.forEach((candidate, index) => {
      const card = renderCandidate(state, record, candidate, index);
      if (card) root.append(card);
    });
    if (candidates.length > 3 && !state.expandedCandidates[record.record_key]) {
      root.append(actionButton('Vis alle kandidater', 'expand-candidates'));
    }
    root.append(element('h2', 'Din afgørelse'));
    const current = state.decisions[record.record_key];
    if (current && (current.outcome || current.review_status)) {
      const selection = current.candidate_id || current.duplicate_of_baseline_record_key || '';
      root.append(element('p', `Nuværende valg: ${current.outcome || current.review_status}${selection ? ` (${selection})` : ''}`, {
        'data-role': 'decision-state',
      }));
    }
    root.append(actionButton('Ingen kandidat passer', 'no-candidate-fits'));
    const search = document.createElement('input');
    search.type = 'search';
    search.value = state.duplicateSearch;
    search.placeholder = 'Søg dubletmål efter navn eller record_key';
    search.setAttribute('data-role', 'duplicate-search');
    root.append(search);
    const duplicate = document.createElement('select');
    duplicate.setAttribute('data-role', 'duplicate-target');
    duplicate.append(element('option', 'Vælg mulig dublet', { value: '' }));
    const duplicateSearch = state.duplicateSearch.toLowerCase();
    state.records.filter(other => other.record_key !== record.record_key)
      .filter(other => !duplicateSearch || `${other.navn || ''} ${other.record_key}`
        .toLowerCase().includes(duplicateSearch))
      .forEach(other => {
      duplicate.append(element('option', other.navn || other.record_key, { value: other.record_key }));
    });
    root.append(duplicate);
    root.append(actionButton('Mulig dublet', 'possible-duplicate'));
    root.append(actionButton('Kan ikke afgøres', 'undecidable'));
    root.append(actionButton('Fortryd seneste valg', 'undo'));
    const navigation = element('p', undefined, { 'data-role': 'navigation' });
    navigation.append(actionButton('Forrige', 'previous'));
    navigation.append(actionButton('Næste', 'next'));
    root.append(navigation);
  }

  function render(state) {
    normalizeSelection(state);
    const saveState = document.querySelector('[data-role="save-state"]');
    if (saveState) saveState.textContent = state.storageError || state.error || state.message;
    const app = document.querySelector('[data-role="app"]');
    if (!app) return;
    app.replaceChildren();
    renderDashboard(state, app);
    renderList(state, app);
    renderRecord(state, app);
  }

  function exportDraft(state) {
    if (state.recoveryBlocked) return {
      schema_version: REVIEW_SCHEMA_VERSION,
      source: clone(state.data.source),
      exported_at: state.now(),
      recovery_blocked: true,
      entries: [],
    };
    return clone({
      schema_version: REVIEW_SCHEMA_VERSION,
      source: state.data.source,
      baseline_sha256: state.data.source && state.data.source.baseline_sha256,
      exported_at: state.now(),
      entries: state.records.map(record => state.decisions[record.record_key] || {
        baseline_record_key: record.record_key,
        outcome: 'undecidable',
        draft: true,
      }),
    });
  }

  function createController(state, options) {
    const controller = {
      get selectedKey() { return state.selectedKey; },
      get storageKey() { return state.storageKey; },
      selectRecord: recordKey => selectRecord(state, recordKey),
      choose: (outcome, payload) => choose(state, outcome, payload),
      undo: () => undo(state),
      next: () => navigate(state, 1),
      previous: () => navigate(state, -1),
      setView: view => setView(state, view),
      exportDraft: () => exportDraft(state),
    };
    controller.download = () => options.download(controller.exportDraft());
    return controller;
  }

  function init({ data, storage = global.localStorage, now = () => new Date().toISOString(), download = () => {} }) {
    if (global.__DAA1939ReviewCleanup) global.__DAA1939ReviewCleanup();
    const state = restoreOrInitialize(data, storage, now);
    const controller = createController(state, { download });
    const clickListener = event => {
      const target = event.target && event.target.closest && event.target.closest('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      if (action === 'select-record') selectRecord(state, target.dataset.recordKey);
      else if (action === 'set-view') setView(state, target.dataset.view);
      else if (action === 'select-candidate') choose(state, 'human_selected_candidate', { candidate_id: target.dataset.candidateId });
      else if (action === 'no-candidate-fits') choose(state, 'no_candidate_fits', {});
      else if (action === 'possible-duplicate') {
        const field = document.querySelector('[data-role="duplicate-target"]');
        choose(state, 'possible_duplicate', { duplicate_of_baseline_record_key: field && field.value });
      } else if (action === 'undecidable') choose(state, 'undecidable', {});
      else if (action === 'undo') undo(state);
      else if (action === 'next') navigate(state, 1);
      else if (action === 'previous') navigate(state, -1);
      else if (action === 'expand-candidates') {
        state.expandedCandidates[state.selectedKey] = true;
        render(state);
      } else if (action === 'export-draft') controller.download();
    };
    const inputListener = event => {
      const input = event.target;
      if (input && input.matches && input.matches('[data-role="duplicate-search"]')) {
        state.duplicateSearch = input.value;
        render(state);
      }
    };
    document.addEventListener('click', clickListener);
    document.addEventListener('input', inputListener);
    global.__DAA1939ReviewCleanup = () => {
      document.removeEventListener('click', clickListener);
      document.removeEventListener('input', inputListener);
    };
    render(state);
    return controller;
  }

  global.DAA1939Review = { init };
})(window);

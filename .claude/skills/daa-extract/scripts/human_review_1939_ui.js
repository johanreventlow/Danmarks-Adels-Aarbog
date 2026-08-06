(function (global) {
  'use strict';

  const OUTCOMES = new Set([
    'human_selected_candidate', 'no_candidate_fits', 'possible_duplicate', 'undecidable',
  ]);
  const FINAL_LEGACY_STATUSES = new Set(['accepteret', 'eksplicit_dublet', 'menneskeark']);
  const BROWSER_DECISION_FIELDS = new Set([
    'baseline_record_key', 'outcome', 'candidate_id', 'duplicate_of_baseline_record_key',
    'decided_at', 'draft', 'reason',
  ]);
  const REVIEW_SCHEMA_VERSION = 1;
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
      }, Object.create(null));
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

  function dictionary(entries) {
    const result = Object.create(null);
    (entries || []).forEach(([key, value]) => { result[key] = value; });
    return result;
  }

  function decisionMap(value) {
    if (Array.isArray(value)) {
      const result = Object.create(null);
      value.forEach(entry => {
        if (!entry || typeof entry !== 'object' || typeof entry.baseline_record_key !== 'string'
          || hasOwn(result, entry.baseline_record_key)) throw new Error('Ugyldig kladdepost');
        result[entry.baseline_record_key] = entry;
      });
      return result;
    }
    if (!value || typeof value !== 'object') throw new Error('Ugyldig kladde');
    return dictionary(Object.entries(value));
  }

  function candidatesContain(record, candidateId) {
    return typeof candidateId === 'string' && Array.isArray(record.candidates)
      && record.candidates.some(candidate => candidate.candidate_id === candidateId);
  }

  function provisionalFields(outcome) {
    const common = ['baseline_record_key', 'outcome', 'decided_at'];
    if (outcome === 'human_selected_candidate') return common.concat('candidate_id');
    if (outcome === 'possible_duplicate') return common.concat('duplicate_of_baseline_record_key');
    if (outcome === 'no_candidate_fits' || outcome === 'undecidable') return common.concat('reason');
    throw new Error('Ukendt udfald');
  }

  function validateProvisionalChoice(decision, exactFields) {
    if (!decision || typeof decision !== 'object' || !OUTCOMES.has(decision.outcome)) {
      throw new Error('Ukendt udfald');
    }
    const expected = new Set(provisionalFields(decision.outcome));
    if (exactFields && (Object.keys(decision).length !== expected.size
      || Object.keys(decision).some(field => !expected.has(field)))) {
      throw new Error('Cacheudfald har uventede eller manglende felter');
    }
    if (!exactFields && Object.keys(decision).some(
      field => BROWSER_DECISION_FIELDS.has(field) && !expected.has(field),
    )) throw new Error('Udfald har uforenelige browserfelter');
    expected.forEach(field => {
      if (!hasOwn(decision, field)) throw new Error('Udfald mangler et påkrævet felt');
    });
    if (typeof decision.baseline_record_key !== 'string' || !decision.baseline_record_key
      || typeof decision.decided_at !== 'string' || !decision.decided_at.trim()) {
      throw new Error('Udfaldets nøgle eller tidspunkt er ugyldigt');
    }
    if (decision.outcome === 'human_selected_candidate'
      && (typeof decision.candidate_id !== 'string' || !decision.candidate_id)) {
      throw new Error('Udfaldets kandidat er ugyldig');
    }
    if (decision.outcome === 'possible_duplicate'
      && (typeof decision.duplicate_of_baseline_record_key !== 'string'
        || !decision.duplicate_of_baseline_record_key)) {
      throw new Error('Udfaldets dubletmål er ugyldigt');
    }
    if ((decision.outcome === 'no_candidate_fits' || decision.outcome === 'undecidable')
      && (typeof decision.reason !== 'string' || !decision.reason.trim())) {
      throw new Error('Skriv en begrundelse for dette udfald');
    }
    return true;
  }

  function cacheEntry(decision) {
    const fields = provisionalFields(decision.outcome);
    const entry = Object.fromEntries(fields.map(field => [field, clone(decision[field])]));
    validateProvisionalChoice(entry, true);
    return entry;
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
    if (hasOutcome || typeof decision.reason !== 'string' || !decision.reason.trim()) {
      throw new Error('Ugyldig menneskearkpost');
    }
    if (!hasOutcome && (hasOwn(decision, 'candidate_id') || hasOwn(decision, 'duplicate_of_baseline_record_key'))) {
      throw new Error('Ugyldig menneskearkpost');
    }
  }

  function validateDecisionState(value, recordByKey) {
    const decisions = decisionMap(value);
    const result = Object.create(null);
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
      validateProvisionalChoice(decision, false);
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
    state.decisions = Object.create(null);
    state.storageError = message;
  }

  function sameValue(left, right) {
    return sourceIdentity({ value: left }) === sourceIdentity({ value: right });
  }

  function overlayCachedDecisions(modelDecisions, restored) {
    const browserFields = new Set([
      'baseline_record_key', 'outcome', 'candidate_id', 'duplicate_of_baseline_record_key',
      'decided_at', 'reason',
    ]);
    const result = dictionary(Object.entries(modelDecisions).map(([key, value]) => [key, clone(value)]));
    Object.entries(restored).forEach(([recordKey, cached]) => {
      validateProvisionalChoice(cached, true);
      const model = result[recordKey] || { baseline_record_key: recordKey };
      if (model.review_status && model.review_status !== 'unreviewed') {
        throw new Error('Endelige legacy-afgørelser må ikke ændres af cache');
      }
      Object.entries(cached).forEach(([field, value]) => {
        if (!browserFields.has(field)) throw new Error('Cache må kun indeholde browserudfald');
        if (field !== 'baseline_record_key' && hasOwn(model, field) && !sameValue(model[field], value)) {
          throw new Error('Cachemetadata matcher ikke den aktuelle kilde');
        }
        if (browserFields.has(field)) return;
        if (!hasOwn(model, field) || !sameValue(model[field], value)) {
          throw new Error('Cachemetadata matcher ikke den aktuelle kilde');
        }
      });
      result[recordKey] = Object.assign(Object.create(null), model,
        Object.fromEntries(Object.entries(cached).filter(([field]) => browserFields.has(field))));
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
      decisions: Object.create(null),
      selectedKey: records[0] && records[0].record_key,
      activeView: data.default_view || 'required',
      recordSearch: '',
      expandedCandidates: Object.create(null),
      duplicateSearch: '',
      undoStack: [],
      storageKey: storageKeyFor(data),
      storage,
      now,
      message: 'Klar. Ændringer gemmes automatisk lokalt.',
      error: '',
      storageError: '',
      recoveryBlocked: false,
      sourceBlockedCount: null,
    };
    const sourceBlockedCount = data && data.summary && data.summary.source_blocked;
    if (!Number.isInteger(sourceBlockedCount) || sourceBlockedCount < 0) {
      blockRecovery(state, 'Kildeoptællingen kan ikke bruges sikkert.');
      return state;
    }
    state.sourceBlockedCount = sourceBlockedCount;
    const modelDecisions = dictionary(records
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
      if (!hasOwn(parsed, 'decisions') || hasOwn(parsed, 'entries')
        || !parsed.decisions || typeof parsed.decisions !== 'object'
        || Array.isArray(parsed.decisions)) {
        blockRecovery(state, 'Den lokale kladde har en ugyldig beslutningsbeholder.');
        return state;
      }
      const restored = decisionMap(parsed.decisions);
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
    if (!decision) return false;
    if (FINAL_LEGACY_STATUSES.has(decision.review_status)) return true;
    try {
      return validateProvisionalChoice(decision, false);
    } catch (_) {
      return false;
    }
  }

  function keysForView(state, view) {
    if (view === 'completed') return state.records
      .filter(record => completed(state, record.record_key))
      .map(record => record.record_key);
    const configured = (state.data.views && state.data.views[view]) || [];
    return configured.filter(key => state.recordByKey.has(key));
  }

  function visibleKeys(state) {
    const query = state.recordSearch.trim().toLowerCase();
    return keysForView(state, state.activeView).filter(key => {
      const record = state.recordByKey.get(key);
      return !query || `${record && record.navn || ''} ${key}`.toLowerCase().includes(query);
    });
  }

  function normalizeSelection(state) {
    const keys = visibleKeys(state);
    if (!keys.includes(state.selectedKey)) state.selectedKey = keys[0];
  }

  function persist(state) {
    if (state.recoveryBlocked) throw new Error('Gendannelse er blokeret');
    validateDecisionState(state.decisions, state.recordByKey);
    state.storage.setItem(state.storageKey, JSON.stringify({
      schema_version: REVIEW_SCHEMA_VERSION,
      source: state.data.source,
      decisions: dictionary(Object.entries(state.decisions)
        .filter(([, decision]) => hasOwn(decision, 'outcome'))
        .map(([recordKey, decision]) => [recordKey, cacheEntry(decision)])),
    }));
  }

  function showSaved(state, message) {
    state.error = '';
    state.storageError = '';
    state.message = message;
  }

  function showStorageError(state) {
    state.storageError = 'Kunne ikke gemme lokalt. Dit valg er ikke bekræftet eller flyttet frem.';
  }

  function validateUiChoice(state, outcome, payload) {
    const record = state.recordByKey.get(state.selectedKey);
    if (!record || !OUTCOMES.has(outcome)) throw new Error('Ugyldigt valg');
    const existing = state.decisions[record.record_key];
    if (record.queue_class === 'auto_resolved' && !record.is_audit) {
      throw new Error('Automatiske poster uden kontrolprøve er skrivebeskyttede');
    }
    if (existing && FINAL_LEGACY_STATUSES.has(existing.review_status)) {
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
    delete decision.reason;
    decision.outcome = outcome;
    decision.decided_at = state.now();
    if (outcome === 'human_selected_candidate') {
      if (Object.keys(payload).some(field => field !== 'candidate_id')) {
        throw new Error('Ugyldige felter for kandidatvalg');
      }
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
      if (Object.keys(payload).some(field => field !== 'duplicate_of_baseline_record_key')) {
        throw new Error('Ugyldige felter for dubletvalg');
      }
      const target = payload.duplicate_of_baseline_record_key;
      if (hasOwn(payload, 'candidate_id') || !state.recordByKey.has(target)
        || target === record.record_key) {
        throw new Error('Vælg en anden kendt historisk post som dubletmål');
      }
      decision.duplicate_of_baseline_record_key = target;
    }
    if (outcome === 'no_candidate_fits' || outcome === 'undecidable') {
      if (Object.keys(payload).some(field => field !== 'reason')) {
        throw new Error('Ugyldigt udvalg for dette udfald');
      }
      if (typeof payload.reason !== 'string' || !payload.reason.trim()) {
        throw new Error('Skriv en begrundelse for dette udfald');
      }
      decision.reason = payload.reason.trim();
    }
    validateProvisionalChoice(decision, false);
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

  function isCompactViewport() {
    return typeof global.matchMedia === 'function'
      && global.matchMedia('(max-width: 720px)').matches;
  }

  function setCompactSidebarOpen(open) {
    const sidebar = document.querySelector('aside');
    const toggle = document.querySelector('[data-action="toggle-sidebar"]');
    if (!sidebar || !toggle) return;
    const expanded = isCompactViewport() && open;
    sidebar.setAttribute('data-mobile-open', String(expanded));
    toggle.setAttribute('aria-expanded', String(expanded));
  }

  function closeCompactSidebar() {
    if (isCompactViewport()) setCompactSidebarOpen(false);
  }

  function selectRecord(state, recordKey) {
    if (!state.recordByKey.has(recordKey)) return false;
    state.selectedKey = recordKey;
    render(state);
    closeCompactSidebar();
    return true;
  }

  function setView(state, view) {
    if (!['required', 'audit', 'completed'].includes(view)) return false;
    state.activeView = view;
    state.recordSearch = '';
    normalizeSelection(state);
    render(state);
    closeCompactSidebar();
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

  function isActionable(state, record) {
    if (state.recoveryBlocked || (record.queue_class === 'auto_resolved' && !record.is_audit)) return false;
    const decision = state.decisions[record.record_key];
    return !(decision && FINAL_LEGACY_STATUSES.has(decision.review_status));
  }

  function renderDashboard(state, root) {
    const dashboard = element('section', undefined, { 'data-role': 'dashboard' });
    const names = { required: 'Kræver menneskeark', audit: 'Stikprøver', completed: 'Afsluttede' };
    ['required', 'audit', 'completed'].forEach(view => {
      const count = keysForView(state, view).length;
      const button = actionButton(`${names[view]} (${count})`, 'set-view', { view });
      button.dataset.view = view;
      if (view === state.activeView) button.setAttribute('aria-current', 'true');
      dashboard.append(button);
    });
    if (state.sourceBlockedCount !== null) {
      dashboard.append(element('p', `Kildeblokerede: ${state.sourceBlockedCount}`, {
        'data-role': 'source-blocked-count',
      }));
    }
    dashboard.append(actionButton('Eksportér kladde', 'export-draft'));
    root.append(dashboard);
  }

  function renderList(state, root) {
    const list = element('nav', undefined, { 'data-role': 'record-list', 'aria-label': 'Poster' });
    visibleKeys(state).forEach(recordKey => {
      const record = state.recordByKey.get(recordKey);
      const button = actionButton(undefined, 'select-record', { recordKey });
      button.append(element('span', record.navn || '(uden navn)'));
      const decision = state.decisions[recordKey];
      let status = 'Mangler';
      let statusKind = 'missing';
      if (decision && FINAL_LEGACY_STATUSES.has(decision.review_status)) {
        status = 'Afsluttet';
        statusKind = 'final';
      } else if (completed(state, recordKey)) {
        status = 'Kladde gemt';
        statusKind = 'draft';
      }
      button.append(element('span', status, {
        'data-role': 'record-status', 'data-status': statusKind,
      }));
      if (recordKey === state.selectedKey) button.setAttribute('aria-current', 'true');
      list.append(button);
    });
    root.append(list);
  }

  function renderSidebar(state, root) {
    root.replaceChildren();
    renderDashboard(state, root);
    const allKeys = keysForView(state, state.activeView);
    const missing = allKeys.filter(key => !completed(state, key)).length;
    root.append(element('p', `${missing} mangler af ${allKeys.length}`, {
      'data-role': 'missing-count',
    }));
    const search = document.createElement('input');
    search.type = 'search';
    search.value = state.recordSearch;
    search.placeholder = 'Søg efter navn';
    search.setAttribute('aria-label', 'Søg efter navn');
    search.setAttribute('data-role', 'record-search');
    root.append(search);
    renderList(state, root);
  }

  function renderCandidate(state, record, candidate) {
    const allVisible = state.expandedCandidates[record.record_key];
    const initiallyVisible = Array.isArray(record.initial_candidate_ids)
      && record.initial_candidate_ids.includes(candidate.candidate_id);
    if (!allVisible && !initiallyVisible) return null;
    const details = element('details', undefined, { class: 'candidate' });
    if (initiallyVisible) details.open = true;
    const pdfLabel = (candidate.pdf_pages || []).join('-') || 'ukendt';
    const exactTextFallbackMessages = {
      entydigt_tekstanker_uden_forventet_side:
        'Teksten er fundet entydigt i Calamari-OCR uden for det gamle sidetal.',
      entydigt_tekstanker_uden_parserkandidat:
        'Teksten er fundet entydigt i Calamari-OCR, men parseren har ikke afgrænset en post.',
    };
    const exactTextFallbackMessage = exactTextFallbackMessages[candidate.rank_reason];
    const isExactTextFallback = Boolean(exactTextFallbackMessage);
    details.append(element('summary', `Mulig kildepost · PDF s. ${pdfLabel}`));
    details.append(element('p', `PDF s. ${(candidate.pdf_pages || []).join('-')} · Calamari-scan ${(candidate.calamari_pages || []).join('-')}`));
    details.append(element('p', isExactTextFallback
      ? exactTextFallbackMessage
      : 'Boksens start og slut er parserens foreslåede postgrænse.'));
    if (isExactTextFallback) {
      details.append(element('h3', 'Calamari-OCR – entydigt tekstfund', { class: 'source-label' }));
      details.append(element('pre', candidate.raw_text || '', {
        'data-role': 'calamari-source', class: 'source-text',
      }));
    } else if (typeof candidate.calamari_verbatim_text === 'string'
      && typeof candidate.raw_verbatim_text === 'string') {
      details.append(element('h3', 'Calamari-OCR – eksakt kildeudsnit', { class: 'source-label' }));
      details.append(element('pre', candidate.calamari_verbatim_text, {
        'data-role': 'calamari-source', class: 'source-text',
      }));
      details.append(element('h3', 'Rå OCR – samme kildepost', { class: 'source-label' }));
      details.append(element('pre', candidate.raw_verbatim_text, {
        'data-role': 'raw-source', class: 'source-text',
      }));
    } else {
      details.append(element('h3', 'Parserens Calamari-OCR-udsnit', { class: 'source-label' }));
      details.append(element('pre', candidate.raw_text || '', {
        'data-role': 'parser-source', class: 'source-text',
      }));
    }
    const technicalEvidence = [];
    if (candidate.details) {
      technicalEvidence.push([candidate.details, 'Klassifikatorens evidens', 'classifier']);
    }
    if (candidate.accepted_review_details) {
      technicalEvidence.push([
        candidate.accepted_review_details, 'Accepteret review-evidens', 'accepted-review',
      ]);
    }
    if (!candidate.details) {
      technicalEvidence.push([
        { candidate_id: candidate.candidate_id }, 'Tekniske detaljer', 'candidate-identity',
      ]);
    }
    technicalEvidence.forEach(([evidence, label, kind]) => {
      if (!evidence || typeof evidence !== 'object') return;
      const technical = element('details', undefined, {
        'data-role': 'candidate-details', 'data-evidence-kind': kind,
      });
      technical.append(element('summary', label));
      technical.append(element('pre', JSON.stringify(evidence, null, 2)));
      details.append(technical);
    });
    if (isActionable(state, record)) {
      const button = actionButton('Vælg denne kandidat', 'select-candidate', { candidateId: candidate.candidate_id });
      const decision = state.decisions[record.record_key];
      if (decision && decision.candidate_id === candidate.candidate_id) button.setAttribute('aria-pressed', 'true');
      details.append(button);
    }
    return details;
  }

  function renderDuplicateOptions(state, record, duplicate) {
    duplicate.replaceChildren(element('option', 'Vælg mulig dublet', { value: '' }));
    const duplicateSearch = state.duplicateSearch.toLowerCase();
    visibleKeys(state).map(key => state.recordByKey.get(key))
      .filter(other => other && other.record_key !== record.record_key)
      .filter(other => !duplicateSearch || `${other.navn || ''} ${other.record_key}`
        .toLowerCase().includes(duplicateSearch))
      .forEach(other => {
        duplicate.append(element('option', other.navn || other.record_key, { value: other.record_key }));
      });
  }

  function decisionStatusText(state, current) {
    if (current.candidate_id) {
      return current.review_status === 'accepteret'
        ? 'Kildeposten er accepteret.' : 'Kildepost valgt.';
    }
    if (current.duplicate_of_baseline_record_key) {
      const duplicate = state.recordByKey.get(current.duplicate_of_baseline_record_key);
      return `Mulig dublet: ${duplicate && duplicate.navn || 'anden historisk post'}.`;
    }
    const labels = {
      no_candidate_fits: 'Ingen kandidat passer.',
      undecidable: 'Kan ikke afgøres.',
      menneskeark: 'Afsluttet som menneskeark.',
    };
    return labels[current.outcome] || labels[current.review_status]
      || 'Afgørelse gemt.';
  }

  function renderRecord(state, root) {
    const record = state.recordByKey.get(state.selectedKey);
    if (!record) {
      root.append(element('p', 'Der er ingen poster i denne visning.'));
      return;
    }
    root.append(element('h1', record.navn || '(uden navn)'));
    const candidateCount = Array.isArray(record.candidates) ? record.candidates.length : 0;
    root.append(element('p', candidateCount === 1
      ? `Er denne kildepost den nævnte person: ${record.navn || '(uden navn)'}?`
      : `Passer en af kildeposterne nedenfor til den nævnte person: ${record.navn || '(uden navn)'}?`, {
      'data-role': 'review-question',
    }));
    root.append(element('p', `PDF-sider: ${record.sider || 'ukendt'} · Klasse: ${record.queue_class} · Årsag: ${record.reason_da || record.reason_code || 'ukendt'}`));
    root.append(element('p', record.boundary_context
      || 'Calamari: ukendt · rå OCR: ukendt. Kræver menneskelig vurdering.', {
      'data-role': 'boundary-context',
    }));
    if (record.is_audit) root.append(element('p', 'Kontrolprøve: denne automatiske afgørelse skal også læses af et menneske.', { 'data-role': 'audit-label' }));
    root.append(element('h2', 'Gammel kildetekst'));
    root.append(element('pre', record.narrative || ''));
    root.append(element('h2', 'Ny OCR: kandidatposter'));
    const candidates = Array.isArray(record.candidates) ? record.candidates : [];
    if (!candidates.length) root.append(element('p', 'Ingen parserkandidat på samme PDF-side.'));
    candidates.forEach(candidate => {
      const card = renderCandidate(state, record, candidate);
      if (card) root.append(card);
    });
    const hasHiddenCandidates = candidates.some(candidate =>
      !Array.isArray(record.initial_candidate_ids)
      || !record.initial_candidate_ids.includes(candidate.candidate_id));
    if (hasHiddenCandidates && !state.expandedCandidates[record.record_key]) {
      const candidateTotal = Number.isInteger(record.candidate_count)
        ? record.candidate_count : candidates.length;
      root.append(actionButton(`Vis alle kandidater (${candidateTotal})`, 'expand-candidates'));
    }
    root.append(element('h2', 'Din afgørelse'));
    const current = state.decisions[record.record_key];
    if (current && (current.outcome || current.review_status)) {
      root.append(element('p', `Nuværende valg: ${decisionStatusText(state, current)}`, {
        'data-role': 'decision-state',
      }));
    }
    const navigation = element('p', undefined, { 'data-role': 'navigation' });
    navigation.append(actionButton('Forrige', 'previous'));
    navigation.append(actionButton('Næste', 'next'));
    if (!isActionable(state, record)) {
      root.append(element('p', 'Denne post er skrivebeskyttet og kan kun inspiceres her.', {
        'data-role': 'read-only-label',
      }));
      root.append(navigation);
      return;
    }
    const controls = element('section', undefined, { 'data-role': 'decision-controls' });
    const reasonLabel = element('label', 'Begrundelse for “Ingen kandidat passer” eller “Kan ikke afgøres”');
    const reason = document.createElement('textarea');
    reason.setAttribute('data-role', 'decision-reason');
    reason.value = current && typeof current.reason === 'string' ? current.reason : '';
    reasonLabel.append(reason);
    controls.append(reasonLabel);
    controls.append(actionButton('Ingen kandidat passer', 'no-candidate-fits'));
    const search = document.createElement('input');
    search.type = 'search';
    search.value = state.duplicateSearch;
    search.placeholder = 'Søg dubletmål efter navn eller record_key';
    search.setAttribute('data-role', 'duplicate-search');
    controls.append(search);
    const duplicate = document.createElement('select');
    duplicate.setAttribute('data-role', 'duplicate-target');
    renderDuplicateOptions(state, record, duplicate);
    controls.append(duplicate);
    controls.append(actionButton('Mulig dublet', 'possible-duplicate'));
    controls.append(actionButton('Kan ikke afgøres', 'undecidable'));
    controls.append(actionButton('Fortryd seneste valg', 'undo'));
    controls.append(navigation);
    root.append(controls);
  }

  function render(state) {
    normalizeSelection(state);
    const saveState = document.querySelector('[data-role="save-state"]');
    if (saveState) saveState.textContent = state.storageError || state.error || state.message;
    const app = document.querySelector('[data-role="app"]');
    const sidebar = document.querySelector('[data-role="sidebar-navigation"]');
    if (!app || !sidebar) return;
    app.replaceChildren();
    renderSidebar(state, sidebar);
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
    setCompactSidebarOpen(false);
    const state = restoreOrInitialize(data, storage, now);
    const controller = createController(state, { download });
    const clickListener = event => {
      const target = event.target && event.target.closest && event.target.closest('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      if (action === 'select-record') selectRecord(state, target.dataset.recordKey);
      else if (action === 'set-view') setView(state, target.dataset.view);
      else if (action === 'select-candidate') choose(state, 'human_selected_candidate', { candidate_id: target.dataset.candidateId });
      else if (action === 'no-candidate-fits') {
        const field = document.querySelector('[data-role="decision-reason"]');
        choose(state, 'no_candidate_fits', { reason: field && field.value });
      }
      else if (action === 'possible-duplicate') {
        const field = document.querySelector('[data-role="duplicate-target"]');
        choose(state, 'possible_duplicate', { duplicate_of_baseline_record_key: field && field.value });
      } else if (action === 'undecidable') {
        const field = document.querySelector('[data-role="decision-reason"]');
        choose(state, 'undecidable', { reason: field && field.value });
      }
      else if (action === 'undo') undo(state);
      else if (action === 'next') navigate(state, 1);
      else if (action === 'previous') navigate(state, -1);
      else if (action === 'toggle-sidebar') {
        const sidebar = document.querySelector('aside');
        setCompactSidebarOpen(!(sidebar && sidebar.getAttribute('data-mobile-open') === 'true'));
      }
      else if (action === 'expand-candidates') {
        state.expandedCandidates[state.selectedKey] = true;
        render(state);
      } else if (action === 'export-draft') controller.download();
    };
    const inputListener = event => {
      const input = event.target;
      if (input && input.matches && input.matches('[data-role="duplicate-search"]')) {
        state.duplicateSearch = input.value;
        const record = state.recordByKey.get(state.selectedKey);
        const duplicate = document.querySelector('[data-role="duplicate-target"]');
        if (record && duplicate) renderDuplicateOptions(state, record, duplicate);
      } else if (input && input.matches && input.matches('[data-role="record-search"]')) {
        state.recordSearch = input.value;
        normalizeSelection(state);
        const sidebar = document.querySelector('[data-role="sidebar-navigation"]');
        const app = document.querySelector('[data-role="app"]');
        const missingCount = sidebar && sidebar.querySelector('[data-role="missing-count"]');
        const oldList = sidebar && sidebar.querySelector('[data-role="record-list"]');
        if (missingCount) {
          const allKeys = keysForView(state, state.activeView);
          missingCount.textContent = `${allKeys.filter(key => !completed(state, key)).length} mangler af ${allKeys.length}`;
        }
        if (sidebar && oldList) {
          oldList.remove();
          renderList(state, sidebar);
        }
        if (app) {
          app.replaceChildren();
          renderRecord(state, app);
        }
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

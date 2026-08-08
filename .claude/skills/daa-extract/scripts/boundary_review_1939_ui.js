(function (global) {
  'use strict';

  const {
    element, actionButton, clone, hasOwn, dictionary, downloadJson,
    readStoredDraft, writeStoredDraft,
  } = global.DAAReviewShared;

  const SCHEMA_VERSION = 1;
  // graense_flyttet og hul_lagt_til_post hører til fase 2: de kræver et valgt
  // skæringspunkt og en afløsning af accepteret evidens.
  const VERDICTS = new Set([
    'graense_ok', 'graense_forkert', 'hul_ejerloest', 'manglende_post',
    'kan_ikke_afgoeres',
  ]);
  const REASON_REQUIRED = new Set(['graense_forkert', 'kan_ikke_afgoeres']);
  const SIGNAL_DA = {
    mangler_eget_hoved: 'Posten begynder ikke med sit eget trykte hoved.',
    slugt_hoved: 'Spændet bærer en senere søskendes trykte hoved.',
    nummerspring: 'De trykte numre står i anden rækkefølge end teksten.',
    laengdeafvigelse: 'Spændet er markant kortere eller længere end søskendene.',
  };
  const VERDICT_DA = {
    graense_ok: 'Grænsen er korrekt',
    graense_forkert: 'Grænsen er forkert',
    hul_ejerloest: 'Hullet er ejerløst',
    manglende_post: 'Der mangler en post',
    kan_ikke_afgoeres: 'Kan ikke afgøres',
  };

  function storageKeyFor(data) {
    return `daa1939-graenser:v${SCHEMA_VERSION}:${JSON.stringify(data.source || {})}`;
  }

  function quarantineMessage(state) {
    const items = Object.values(state.quarantined);
    if (!items.length) return '';
    const reasons = items.map(item => item.aarsag).join('; ');
    return `${items.length} gemt dom${items.length === 1 ? '' : 'me'} i karantæne: ${reasons}`;
  }

  function quarantine(state, key, entry, aarsag) {
    state.quarantined[key] = { entry: clone(entry), aarsag };
  }

  function restoreNotes(state, savedNotes) {
    const notes = Array.isArray(savedNotes) ? savedNotes : Object.values(savedNotes || {});
    notes.forEach((note, index) => {
      if (!note || typeof note !== 'object'
        || typeof note.baseline_record_key !== 'string'
        || typeof note.staar !== 'string' || !note.staar.trim()
        || typeof note.burde !== 'string' || !note.burde.trim()
        || typeof note.raa_bekraefter !== 'boolean'
        || typeof note.noted_at !== 'string') {
        quarantine(state, `ocr-note-${index}`, note, 'En gemt OCR-note er ugyldig.');
        return;
      }
      state.notes[note.baseline_record_key] = clone(note);
    });
  }

  function restore(state) {
    const saved = readStoredDraft(state.storage, state.storageKey);
    if (saved == null) return;
    if (!saved || typeof saved !== 'object' || Array.isArray(saved)) {
      quarantine(state, 'kladde', saved, 'Den gemte kladde har et ugyldigt format.');
      return;
    }
    const savedVerdicts = hasOwn(saved, 'verdicts') ? saved.verdicts : saved;
    const entries = savedVerdicts && typeof savedVerdicts === 'object'
      && !Array.isArray(savedVerdicts) ? Object.entries(savedVerdicts) : [];
    if (!savedVerdicts || typeof savedVerdicts !== 'object' || Array.isArray(savedVerdicts)) {
      quarantine(state, 'domme', savedVerdicts, 'Den gemte domsamling er ugyldig.');
    }
    entries.forEach(([storedId, storedEntry]) => {
      const entry = storedEntry && typeof storedEntry === 'object'
        ? Object.assign({ boundary_id: storedId }, clone(storedEntry)) : storedEntry;
      const boundary = state.byId.get(storedId);
      if (!boundary) {
        quarantine(state, storedId, entry,
          `Grænsen ${storedId} findes ikke længere i denne kilde.`);
      } else if (!entry || typeof entry !== 'object') {
        quarantine(state, storedId, entry, `Den gemte dom for ${storedId} er ugyldig.`);
      } else if (entry.boundary_id !== storedId) {
        quarantine(state, storedId, entry,
          `Den gemte dom for ${storedId} har en anden grænseidentitet.`);
      } else if (entry.revision !== boundary.revision) {
        quarantine(state, storedId, entry,
          `Den gemte dom for ${storedId} har revision ${String(entry.revision)}, men grænsen har revision ${boundary.revision}.`);
      } else if (!VERDICTS.has(entry.verdict)) {
        quarantine(state, storedId, entry, `Den gemte dom for ${storedId} er ukendt.`);
      } else if (REASON_REQUIRED.has(entry.verdict)
        && (typeof entry.begrundelse !== 'string' || !entry.begrundelse.trim())) {
        quarantine(state, storedId, entry, `Den gemte dom for ${storedId} mangler en begrundelse.`);
      } else {
        state.verdicts[storedId] = clone(entry);
      }
    });
    if (hasOwn(saved, 'ocr_noter')) restoreNotes(state, saved.ocr_noter);
    if (saved.quarantined && typeof saved.quarantined === 'object'
      && !Array.isArray(saved.quarantined)) {
      Object.entries(saved.quarantined).forEach(([key, item]) => {
        if (item && typeof item === 'object' && typeof item.aarsag === 'string') {
          state.quarantined[key] = clone(item);
        }
      });
    }
  }

  function persist(state) {
    const error = writeStoredDraft(state.storage, state.storageKey, {
      schema_version: SCHEMA_VERSION,
      source: clone(state.data.source),
      verdicts: clone(state.verdicts),
      ocr_noter: clone(state.notes),
      quarantined: clone(state.quarantined),
    });
    state.message = error || 'Ændringen er gemt lokalt.';
    return !error;
  }

  function record(state, id, verdict, payload) {
    const boundary = state.byId.get(id);
    if (!boundary || !VERDICTS.has(verdict)) {
      state.message = 'Dommen blev afvist, fordi grænsen eller dommen er ukendt.';
      render(state);
      return false;
    }
    const reason = payload && typeof payload.begrundelse === 'string'
      ? payload.begrundelse.trim() : '';
    if (REASON_REQUIRED.has(verdict) && !reason) {
      state.message = 'Skriv en begrundelse for denne dom.';
      render(state);
      return false;
    }
    const previous = hasOwn(state.verdicts, id) ? clone(state.verdicts[id]) : undefined;
    const entry = {
      boundary_id: id,
      revision: boundary.revision,
      verdict,
      decided_at: state.now(),
    };
    if (reason) entry.begrundelse = reason;
    state.verdicts[id] = entry;
    if (!persist(state)) {
      if (previous === undefined) delete state.verdicts[id];
      else state.verdicts[id] = previous;
      render(state);
      return false;
    }
    render(state);
    return true;
  }

  function knownRecordKeys(state) {
    const result = new Set();
    state.byId.forEach(boundary => {
      if (boundary.before && boundary.before.baseline_record_key) {
        result.add(boundary.before.baseline_record_key);
      }
      if (boundary.after && boundary.after.baseline_record_key) {
        result.add(boundary.after.baseline_record_key);
      }
    });
    return result;
  }

  function addNote(state, recordKey, note) {
    if (!knownRecordKeys(state).has(recordKey)
      || !note || typeof note !== 'object'
      || typeof note.staar !== 'string' || !note.staar.trim()
      || typeof note.burde !== 'string' || !note.burde.trim()
      || typeof note.raa_bekraefter !== 'boolean') {
      state.message = 'OCR-noten blev afvist, fordi posten eller noten er ugyldig.';
      render(state);
      return false;
    }
    const previous = hasOwn(state.notes, recordKey) ? clone(state.notes[recordKey]) : undefined;
    state.notes[recordKey] = {
      baseline_record_key: recordKey,
      staar: note.staar.trim(),
      burde: note.burde.trim(),
      raa_bekraefter: note.raa_bekraefter,
      noted_at: state.now(),
    };
    if (!persist(state)) {
      if (previous === undefined) delete state.notes[recordKey];
      else state.notes[recordKey] = previous;
      render(state);
      return false;
    }
    render(state);
    return true;
  }

  function exportDraft(state) {
    return clone({
      schema_version: SCHEMA_VERSION,
      source: state.data.source,
      exported_at: state.now(),
      entries: Object.values(state.verdicts)
        .sort((left, right) => left.boundary_id.localeCompare(right.boundary_id)),
      ocr_noter: Object.values(state.notes)
        .sort((left, right) => left.baseline_record_key.localeCompare(right.baseline_record_key)),
    });
  }

  function renderSidebar(state, sidebar) {
    sidebar.replaceChildren();
    const required = state.data.views.kraever_vurdering || [];
    const quick = state.data.views.hurtig_bekraeftelse || [];
    sidebar.append(actionButton(
      `Kræver vurdering (${required.length})`, 'show-required',
    ));
    sidebar.append(actionButton(
      `Hurtig bekræftelse (${quick.length})`, 'show-quick',
    ));
    const list = element('ul', undefined, { 'data-role': 'boundary-list' });
    const ids = state.activeView === 'hurtig_bekraeftelse' ? quick : required;
    ids.forEach(id => {
      const boundary = state.byId.get(id);
      if (!boundary) return;
      const item = element('li');
      item.append(actionButton(
        `${boundary.before_navn || 'Ukendt'} → ${boundary.after_navn || 'Ukendt'}`,
        'select-boundary', { boundaryId: id },
      ));
      list.append(item);
    });
    sidebar.append(list);
    if (quick.length) {
      sidebar.append(actionButton(
        `Bekræft ${quick.length} porterede huller som ejerløse`, 'bulk-confirm',
      ));
    }
  }

  function renderSignals(boundary) {
    const section = element('section');
    section.append(element('h3', 'Signaler'));
    const list = element('ul');
    (boundary.signals || []).forEach(signal => {
      list.append(element('li', `${signal}: ${SIGNAL_DA[signal] || 'Ukendt signal.'}`));
    });
    if (!(boundary.signals || []).length) list.append(element('li', 'Ingen registrerede signaler.'));
    section.append(list);
    return section;
  }

  function renderNoteFields(boundary) {
    const section = element('section');
    section.append(element('h3', 'OCR-note til en post'));
    section.append(element('p', 'Noten knyttes til postens baseline_record_key, ikke til skæringen.'));
    const target = element('select', undefined, { 'data-role': 'note-record-key' });
    [boundary.before, boundary.after].forEach(record => {
      if (record && record.baseline_record_key) {
        target.append(element('option', record.baseline_record_key, { value: record.baseline_record_key }));
      }
    });
    section.append(target);
    section.append(element('input', undefined, {
      'data-role': 'note-staar', placeholder: 'Der står', type: 'text',
    }));
    section.append(element('input', undefined, {
      'data-role': 'note-burde', placeholder: 'Der burde stå', type: 'text',
    }));
    const label = element('label', ' Rå OCR bekræfter rettelsen');
    label.prepend(element('input', undefined, {
      'data-role': 'note-raw-confirms', type: 'checkbox',
    }));
    section.append(label);
    section.append(actionButton('Gem OCR-note på posten', 'save-note'));
    return section;
  }

  function renderBoundary(state, root) {
    const boundary = state.byId.get(state.selectedId);
    if (!boundary) {
      root.append(element('p', 'Der er ingen grænse i denne visning.'));
      return;
    }
    root.append(element('h1', 'Grænsegennemgang 1939'));
    const sides = element('section', undefined, { 'data-role': 'boundary-evidence' });
    sides.append(element('h2', `Før: ${boundary.before_navn || 'Ukendt navn'}`));
    sides.append(element('p', boundary.before_context || 'Ingen kontekst før skæringen.'));
    sides.append(element('h2', 'Calamari-hullet'));
    sides.append(element('pre', boundary.gap_text || '', { 'data-role': 'gap-text' }));
    sides.append(element('h2', 'Råt OCR-vindue'));
    sides.append(element('pre', boundary.raw_window || '', { 'data-role': 'raw-window' }));
    sides.append(element('h2', `Efter: ${boundary.after_navn || 'Ukendt navn'}`));
    sides.append(element('p', boundary.after_context || 'Ingen kontekst efter skæringen.'));
    root.append(sides);
    root.append(renderSignals(boundary));
    const controls = element('section', undefined, { 'data-role': 'verdict-controls' });
    controls.append(element('h3', 'Dom over grænsen'));
    VERDICTS.forEach(verdict => controls.append(actionButton(VERDICT_DA[verdict], verdict)));
    controls.append(element('textarea', undefined, {
      'data-role': 'reason', placeholder: 'Begrundelse kræves ved forkert eller uafgørlig grænse',
    }));
    root.append(controls);
    root.append(renderNoteFields(boundary));
  }

  function renderQuick(state, root) {
    root.append(element('h1', 'Hurtig bekræftelse af porterede huller'));
    const table = element('table', undefined, { 'data-role': 'quick-boundaries' });
    const head = element('tr');
    ['Før', 'Hul', 'Efter', 'Dom'].forEach(label => head.append(element('th', label)));
    table.append(head);
    (state.data.views.hurtig_bekraeftelse || []).forEach(id => {
      const boundary = state.byId.get(id);
      if (!boundary || !boundary.bulk_confirmable) return;
      const row = element('tr');
      row.append(element('td', boundary.before_navn || 'Ukendt'));
      row.append(element('td', boundary.gap_text || 'Tomt hul'));
      row.append(element('td', boundary.after_navn || 'Ukendt'));
      row.append(element('td', state.verdicts[id]
        ? VERDICT_DA[state.verdicts[id].verdict] : 'Ikke bedømt'));
      table.append(row);
    });
    root.append(table);
    root.append(actionButton('Bekræft alle porterede huller som ejerløse', 'bulk-confirm'));
  }

  function render(state) {
    const saveState = document.querySelector('[data-role="save-state"]');
    if (saveState) {
      saveState.textContent = [state.message, quarantineMessage(state)].filter(Boolean).join(' ');
    }
    const app = document.querySelector('[data-role="app"]');
    const sidebar = document.querySelector('[data-role="sidebar-navigation"]');
    if (!app || !sidebar) return;
    renderSidebar(state, sidebar);
    app.replaceChildren();
    if (state.activeView === 'hurtig_bekraeftelse') renderQuick(state, app);
    else renderBoundary(state, app);
  }

  function init({ data, storage = global.localStorage,
                  now = () => new Date().toISOString(), download = () => {} }) {
    if (typeof global.__DAABoundaryReviewCleanup === 'function') {
      global.__DAABoundaryReviewCleanup();
    }
    const views = data.views || {};
    const required = views.kraever_vurdering || [];
    const quick = views.hurtig_bekraeftelse || [];
    const state = {
      data,
      byId: new Map((data.boundaries || []).map(boundary => [boundary.boundary_id, boundary])),
      verdicts: dictionary([]),
      notes: dictionary([]),
      quarantined: dictionary([]),
      selectedId: required[0] || quick[0],
      activeView: required.length ? 'kraever_vurdering' : 'hurtig_bekraeftelse',
      storage,
      storageKey: storageKeyFor(data),
      now,
      message: 'Klar. Ændringer gemmes automatisk lokalt.',
    };
    restore(state);
    const controller = {
      verdict: (id, verdict, payload) => record(state, id, verdict, payload || {}),
      note: (recordKey, note) => addNote(state, recordKey, note),
      exportDraft: () => exportDraft(state),
      download: () => download(exportDraft(state)),
    };
    const clickListener = event => {
      const target = event.target;
      const action = target && target.getAttribute && target.getAttribute('data-action');
      if (!action) return;
      if (VERDICTS.has(action)) {
        const field = document.querySelector('[data-role="reason"]');
        record(state, state.selectedId, action, { begrundelse: field && field.value });
      } else if (action === 'bulk-confirm') {
        (state.data.views.hurtig_bekraeftelse || []).forEach(id => {
          const boundary = state.byId.get(id);
          if (boundary && boundary.bulk_confirmable) record(state, id, 'hul_ejerloest', {});
        });
      } else if (action === 'export-draft') controller.download();
      else if (action === 'select-boundary') {
        const id = target.getAttribute('data-boundary-id');
        if (state.byId.has(id)) state.selectedId = id;
        render(state);
      } else if (action === 'show-required') {
        state.activeView = 'kraever_vurdering';
        state.selectedId = (state.data.views.kraever_vurdering || [])[0];
        render(state);
      } else if (action === 'show-quick') {
        state.activeView = 'hurtig_bekraeftelse';
        state.selectedId = (state.data.views.hurtig_bekraeftelse || [])[0];
        render(state);
      } else if (action === 'save-note') {
        const recordKey = document.querySelector('[data-role="note-record-key"]');
        const staar = document.querySelector('[data-role="note-staar"]');
        const burde = document.querySelector('[data-role="note-burde"]');
        const rawConfirms = document.querySelector('[data-role="note-raw-confirms"]');
        addNote(state, recordKey && recordKey.value, {
          staar: staar && staar.value,
          burde: burde && burde.value,
          raa_bekraefter: Boolean(rawConfirms && rawConfirms.checked),
        });
      }
    };
    document.addEventListener('click', clickListener);
    global.__DAABoundaryReviewCleanup = () => {
      document.removeEventListener('click', clickListener);
    };
    render(state);
    global.DAABoundaryReview.controller = controller;
    return controller;
  }

  global.DAABoundaryReview = { init };
}(typeof globalThis === 'undefined' ? this : globalThis));

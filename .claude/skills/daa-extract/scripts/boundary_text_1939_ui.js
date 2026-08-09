(function (global) {
  'use strict';

  const LINE_MARKERS = [
    ['boundary', /^=== GRÆNSESKÆRING ===$/],
    ['boundarySignal', /^=== GRÆNSESKÆRING · SIGNAL (mangler_eget_hoved|slugt_hoved)(?:, (mangler_eget_hoved|slugt_hoved))* ===$/],
    ['proposal', /^=== FORSLAG\? SKÆRING ===$/],
    ['cut', /^=== SKÆRING ===$/],
    ['hole', /^=== EJERLØS TEKST · (0|[1-9]\d*) tegn ===$/],
    ['pdf', /^=== PDF-SIDE (0|[1-9]\d*) ===$/],
  ];
  const STORAGE_PREFIX = 'daa-1939-graenseflade:';

  function chars(value) {
    return Array.from(value);
  }

  function charLength(value) {
    return chars(value).length;
  }

  function lineAt(value, charOffset) {
    return chars(value).slice(0, charOffset).filter(character => character === '\n').length + 1;
  }

  function markerKind(line) {
    for (const [kind, pattern] of LINE_MARKERS) {
      if (pattern.test(line)) return kind === 'boundarySignal' ? 'boundary' : kind;
    }
    return null;
  }

  function gateFor(bookText, sourceText, fieldLinesByBookLine) {
    const actual = new TextEncoder().encode(bookText);
    const expected = new TextEncoder().encode(sourceText);
    let byte = 0;
    while (byte < actual.length && byte < expected.length && actual[byte] === expected[byte]) byte += 1;
    if (byte === actual.length && byte === expected.length) {
      return { ok: true, line: null, message: 'bogteksten er urørt' };
    }
    const actualChars = chars(bookText);
    const expectedChars = chars(sourceText);
    let position = 0;
    while (position < actualChars.length && position < expectedChars.length
           && actualChars[position] === expectedChars[position]) position += 1;
    const sourceLine = lineAt(sourceText, position);
    const bookLine = lineAt(bookText, position);
    const line = fieldLinesByBookLine[bookLine - 1]
      || fieldLinesByBookLine[fieldLinesByBookLine.length - 1]
      || 1;
    const result = {
      ok: false,
      line,
      sourceLine,
      message: `bogteksten er ændret ved linje ${line} (kildens linje ${sourceLine})`,
    };
    Object.defineProperty(result, 'sourceOffset', { value: position });
    return result;
  }

  function parseMarkedText(markedText, sourceText) {
    const markers = [];
    const ocrNotes = [];
    const omissions = [];
    const book = [];
    const fieldLinesByBookLine = [];
    let bookOffset = 0;
    let bookTail = '';
    let viewIndex = 0;
    let lineNumber = 1;
    let openOmission = null;
    const viewOffsets = new Map([[0, 0]]);

    function failure(message, line) {
      const result = { ok: false, line, error: `${message} ved linje ${line}` };
      Object.defineProperty(result, 'sourceOffset', { value: bookOffset });
      return result;
    }

    function appendBook(value) {
      book.push(value);
      bookOffset += charLength(value);
      bookTail = (bookTail + value).slice(-2);
    }

    function offsetBeforeTrailingLineBreak() {
      if (bookTail.endsWith('\r\n')) return bookOffset - 2;
      if (bookTail.endsWith('\n') || bookTail.endsWith('\r')) return bookOffset - 1;
      return bookOffset;
    }

    while (viewIndex < markedText.length) {
      if (!viewOffsets.has(bookOffset)) viewOffsets.set(bookOffset, viewIndex);
      let next = markedText.indexOf('\n', viewIndex);
      const end = next === -1 ? markedText.length : next + 1;
      const rawLine = markedText.slice(viewIndex, end);
      const content = rawLine.endsWith('\n')
        ? rawLine.slice(0, rawLine.endsWith('\r\n') ? -2 : -1)
        : rawLine;
      const kind = markerKind(content);
      if (kind) {
        markers.push({ kind, char_offset: bookOffset, text: content });
        viewIndex = end;
        lineNumber += 1;
        continue;
      }
      if (content.startsWith('===')) return failure('ukendt ===-markør', lineNumber);
      if (content === '[[UDELAD]]') {
        if (openOmission !== null) return failure('indlejret UDELAD-tag', lineNumber);
        openOmission = { char_from: bookOffset, line: lineNumber };
        viewIndex = end;
        lineNumber += 1;
        continue;
      }
      if (content === '[[/UDELAD]]') {
        if (openOmission === null) return failure('uparret /UDELAD-tag', lineNumber);
        omissions.push({
          char_from: openOmission.char_from,
          char_to: offsetBeforeTrailingLineBreak(),
        });
        openOmission = null;
        viewIndex = end;
        lineNumber += 1;
        continue;
      }
      const trimmed = content.trim();
      const tagInterior = trimmed.slice(2, -2);
      if (trimmed.startsWith('[[') && trimmed.endsWith(']]')
          && !tagInterior.includes('[[') && !tagInterior.includes(']]')) {
        return failure('ukendt inline-tag', lineNumber);
      }
      fieldLinesByBookLine.push(lineNumber);

      let position = 0;
      while (position < rawLine.length) {
        const opening = rawLine.indexOf('[[', position);
        const closing = rawLine.indexOf(']]', position);
        if (closing !== -1 && (opening === -1 || closing < opening)) {
          return failure('uparret inline-tag', lineNumber);
        }
        if (opening === -1) {
          const tail = rawLine.slice(position);
          appendBook(tail);
          break;
        }
        const plain = rawLine.slice(position, opening);
        appendBook(plain);
        const tagEnd = rawLine.indexOf(']]', opening + 2);
        if (tagEnd === -1) return failure('uparret inline-tag', lineNumber);
        const tag = rawLine.slice(opening, tagEnd + 2);
        if (tag === '[[UDELAD]]') {
          if (openOmission !== null) return failure('indlejret UDELAD-tag', lineNumber);
          openOmission = { char_from: bookOffset, line: lineNumber };
        } else if (tag === '[[/UDELAD]]') {
          if (openOmission === null) return failure('uparret /UDELAD-tag', lineNumber);
          omissions.push({ char_from: openOmission.char_from, char_to: bookOffset });
          openOmission = null;
        } else {
          const match = /^\[\[OCR: ([^\r\n]*?) \| burde stå ([^\r\n]*?)\]\]$/.exec(tag);
          if (!match) return failure('ukendt inline-tag', lineNumber);
          ocrNotes.push({ char_offset: bookOffset, staar: match[1], burde_staa: match[2] });
        }
        position = tagEnd + 2;
      }
      viewIndex = end;
      lineNumber += 1;
    }
    if (openOmission !== null) return failure('uparret UDELAD-tag', openOmission.line);
    const bookText = book.join('');
    if (!viewOffsets.has(bookOffset)) viewOffsets.set(bookOffset, viewIndex);
    const result = {
      ok: true,
      bookText,
      markers,
      ocrNotes,
      omissions,
      gate: gateFor(bookText, sourceText, fieldLinesByBookLine),
    };
    Object.defineProperty(result, 'viewOffsets', { value: viewOffsets });
    return result;
  }

  const LINE_RANK = { pdf: 10, boundary: 20, hole: 30, proposal: 40, cut: 50 };
  const INLINE_RANK = { udelad_start: 0, ocr: 1, udelad_end: 2 };

  function lineMarkerDisplayOffset(source, canonicalOffset) {
    if (canonicalOffset === 0 || ['\n', '\r'].includes(source[canonicalOffset - 1])) {
      return canonicalOffset;
    }
    for (let offset = canonicalOffset; offset < source.length; offset += 1) {
      const character = source[offset];
      if (!/^\s$/u.test(character)) {
        throw new Error(`linjemarkør ved ${canonicalOffset} har ikke-whitespace før næste linjestart`);
      }
      if (character === '\n') return offset + 1;
      if (character === '\r' && source[offset + 1] !== '\n') return offset + 1;
    }
    throw new Error(`linjemarkør ved ${canonicalOffset} har ingen efterfølgende linjestart`);
  }

  function composeMarkedText(sourceText, annotations) {
    const source = chars(sourceText);
    const grouped = new Map();
    annotations.forEach(annotation => {
      const offset = annotation.char_offset;
      if (!Number.isInteger(offset) || offset < 0 || offset > source.length) {
        throw new Error('markør har ugyldig kildetekstposition');
      }
      const displayOffset = Object.hasOwn(LINE_RANK, annotation.kind)
        ? lineMarkerDisplayOffset(source, offset) : offset;
      if (!grouped.has(displayOffset)) grouped.set(displayOffset, []);
      grouped.get(displayOffset).push(annotation);
    });
    const result = [];
    for (let offset = 0; offset <= source.length; offset += 1) {
      const items = grouped.get(offset) || [];
      const lineItems = items.filter(item => Object.hasOwn(LINE_RANK, item.kind))
        .sort((left, right) => LINE_RANK[left.kind] - LINE_RANK[right.kind]
          || String(left.text).localeCompare(String(right.text)));
      lineItems.forEach(item => result.push(item.text + '\n'));
      items.filter(item => Object.hasOwn(INLINE_RANK, item.kind))
        .sort((left, right) => INLINE_RANK[left.kind] - INLINE_RANK[right.kind])
        .forEach(item => {
          if (item.kind === 'ocr') {
            result.push(`[[OCR: ${item.staar} | burde stå ${item.burde_staa}]]`);
          } else if (item.kind === 'udelad_start') result.push('[[UDELAD]]');
          else result.push('[[/UDELAD]]');
        });
      if (offset < source.length) result.push(source[offset]);
    }
    return result.join('');
  }

  function canonicalMarkers(markers, data) {
    const mappings = Array.isArray(data.lineMarkerMappings) ? data.lineMarkerMappings : [];
    return markers.map(marker => {
      const atDisplay = mappings.filter(mapping => mapping.displayOffset === marker.char_offset);
      let mapping = atDisplay.find(candidate => (
        candidate.kind === marker.kind && candidate.text === marker.text
      ));
      if (!mapping && marker.kind === 'cut') {
        mapping = atDisplay.find(candidate => candidate.kind === 'cut')
          || atDisplay.find(candidate => candidate.kind === 'proposal')
          || atDisplay.find(candidate => candidate.kind === 'boundary');
      }
      if (!mapping) mapping = atDisplay.find(candidate => candidate.kind === marker.kind);
      return mapping ? {
        ...marker,
        char_offset: mapping.canonicalOffset,
        originHint: mapping.origin || null,
      } : marker;
    });
  }

  function buildExport(markedText, data, exportedAt) {
    const parsed = parseMarkedText(markedText, data.sourceText);
    if (!parsed.ok) return { ok: false, error: parsed.error };
    if (!parsed.gate.ok) return { ok: false, error: parsed.gate.message };
    const markers = canonicalMarkers(parsed.markers, data);
    const expectedBoundaries = new Set(data.expectedBoundaryOffsets);
    const expectedProposals = new Set(data.expectedProposalOffsets);
    const acceptedByOffset = new Map();
    const proposalMarkers = new Set();
    markers.forEach(marker => {
      if (marker.kind === 'proposal') proposalMarkers.add(marker.char_offset);
      if (marker.kind === 'boundary' || marker.kind === 'cut') {
        if (!acceptedByOffset.has(marker.char_offset)) acceptedByOffset.set(marker.char_offset, []);
        acceptedByOffset.get(marker.char_offset).push(marker);
      }
    });
    const cuts = Array.from(acceptedByOffset).map(([char_offset, accepted]) => {
      const cut = accepted.find(marker => marker.kind === 'cut');
      return {
        char_offset,
        oprindelse: cut && cut.originHint ? cut.originHint
          : expectedProposals.has(char_offset) && cut ? 'forslag_godkendt'
            : expectedBoundaries.has(char_offset) ? 'forudsat'
              : 'bruger',
      };
    }).sort((left, right) => left.char_offset - right.char_offset);
    const kept = data.expectedBoundaryOffsets.filter(offset => acceptedByOffset.has(offset));
    const approvedProposals = data.expectedProposalOffsets.filter(offset => {
      const accepted = acceptedByOffset.get(offset) || [];
      return accepted.some(marker => marker.kind === 'cut');
    });
    const deleted = data.expectedBoundaryOffsets
      .filter(offset => !acceptedByOffset.has(offset))
      .map(char_offset => ({ char_offset, var: 'GRÆNSESKÆRING' }));
    data.expectedProposalOffsets.forEach(char_offset => {
      const accepted = acceptedByOffset.get(char_offset) || [];
      if (!proposalMarkers.has(char_offset)
          && !accepted.some(marker => marker.kind === 'cut')) {
        deleted.push({ char_offset, var: 'FORSLAG' });
      }
    });
    return {
      ok: true,
      value: {
        schema_version: 1,
        source: JSON.parse(JSON.stringify(data.source)),
        exported_at: exportedAt || new Date().toISOString(),
        skaeringer: cuts,
        aendringsregnskab: {
          forudsat: data.expectedBoundaryOffsets.length,
          beholdt: kept.length,
          slettet: data.expectedBoundaryOffsets.length - kept.length,
          tilfoejet: cuts.filter(item => !expectedBoundaries.has(item.char_offset)).length,
          forslag_forudsat: data.expectedProposalOffsets.length,
          forslag_godkendt: approvedProposals.length,
          forslag_bortfaldet: data.expectedProposalOffsets.length - approvedProposals.length,
        },
        slettede: deleted,
        ocr_noter: parsed.ocrNotes,
        udeladelser: parsed.omissions,
      },
    };
  }

  function pageIndexForSourceOffset(pages, sourceOffset) {
    const found = pages.findIndex((page, index) => (
      sourceOffset >= page.charFrom
      && (sourceOffset < page.charTo || (index === pages.length - 1 && sourceOffset === page.charTo))
    ));
    return found === -1 ? 0 : found;
  }

  function newlineCount(value) {
    return chars(value).filter(character => character === '\n').length;
  }

  function validatePageTexts(pageTexts, data) {
    const markedText = pageTexts.join('');
    const parsed = parseMarkedText(markedText, data.sourceText);
    const gate = parsed.ok ? parsed.gate : parsed;
    if (parsed.ok && gate.ok) return { ok: true, message: gate.message };
    const sourceOffset = Number.isInteger(gate.sourceOffset) ? gate.sourceOffset : 0;
    const pageIndex = pageIndexForSourceOffset(data.pages, sourceOffset);
    const precedingLines = pageTexts.slice(0, pageIndex)
      .reduce((total, pageText) => total + newlineCount(pageText), 0);
    const globalFieldLine = Number.isInteger(gate.line) ? gate.line : 1;
    const pageLine = Math.max(1, globalFieldLine - precedingLines);
    const page = data.pages[pageIndex];
    const baseMessage = parsed.ok
      ? 'bogteksten er ændret'
      : gate.error.replace(/ ved linje \d+$/, '');
    return {
      ok: false,
      pageIndex,
      pdfPage: page.pdfPage,
      pageLine,
      message: `${baseMessage} på side ${page.pdfPage} ved linje ${pageLine}`,
    };
  }

  function reviewedPdfPages(data, reviewedPages) {
    const allowed = new Set(data.pages.map(page => page.pdfPage));
    return Array.from(new Set((reviewedPages || []).filter(page => allowed.has(page))))
      .sort((left, right) => left - right);
  }

  function buildExportFromPages(pageTexts, data, exportedAt, reviewedPages) {
    const exported = buildExport(pageTexts.join(''), data, exportedAt);
    if (!exported.ok) return exported;
    exported.value.sider = {
      i_alt: data.pages.length,
      gennemgaaet: reviewedPdfPages(data, reviewedPages),
    };
    return exported;
  }

  function pageProgress(data, reviewedPages, currentIndex) {
    const reviewed = new Set(reviewedPdfPages(data, reviewedPages));
    const missing = data.pages.length - reviewed.size;
    return {
      counter: `side ${currentIndex + 1} af ${data.pages.length} · ${missing} mangler`,
      items: data.pages.map(page => (
        `PDF-side ${page.pdfPage} · ${reviewed.has(page.pdfPage) ? 'gennemgået' : 'mangler'}`
        + ` · ${page.counts.ejerloes} ejerløs`
        + ` · ${page.counts.forslag} forslag`
        + ` · ${page.counts.signaler} signal`
      )),
    };
  }

  function togglePageCompletion(data, reviewedPages, currentIndex, gateOk) {
    const reviewed = new Set(reviewedPdfPages(data, reviewedPages));
    const pdfPage = data.pages[currentIndex].pdfPage;
    if (reviewed.has(pdfPage)) {
      reviewed.delete(pdfPage);
      return {
        reviewedPages: Array.from(reviewed).sort((left, right) => left - right),
        currentIndex,
        changed: true,
      };
    }
    if (!gateOk) return {
      reviewedPages: Array.from(reviewed), currentIndex, changed: false,
    };
    reviewed.add(pdfPage);
    let nextIndex = data.pages.findIndex((page, index) => (
      index > currentIndex && !reviewed.has(page.pdfPage)
    ));
    if (nextIndex === -1) {
      nextIndex = data.pages.findIndex(page => !reviewed.has(page.pdfPage));
    }
    if (nextIndex === -1) nextIndex = currentIndex;
    return {
      reviewedPages: Array.from(reviewed).sort((left, right) => left - right),
      currentIndex: nextIndex,
      changed: true,
    };
  }

  function nearestLineOffset(sourceText, wanted) {
    const source = chars(sourceText);
    const offsets = [0];
    source.forEach((character, index) => {
      if (character === '\n' && index + 1 <= source.length) offsets.push(index + 1);
    });
    return offsets.reduce((best, offset) => (
      Math.abs(offset - wanted) < Math.abs(best - wanted) ? offset : best
    ), offsets[0]);
  }

  function restoreBookText(markedText, sourceText) {
    const parsed = parseMarkedText(markedText, sourceText);
    if (!parsed.ok) return { ok: false, error: parsed.error };
    const annotations = parsed.markers.map(marker => ({
      ...marker,
      char_offset: nearestLineOffset(sourceText, marker.char_offset),
    }));
    parsed.ocrNotes.forEach(note => annotations.push({
      kind: 'ocr', ...note,
      char_offset: Math.max(0, Math.min(charLength(sourceText), note.char_offset)),
    }));
    parsed.omissions.forEach(omission => {
      annotations.push({ kind: 'udelad_start', char_offset: Math.max(0, Math.min(charLength(sourceText), omission.char_from)) });
      annotations.push({ kind: 'udelad_end', char_offset: Math.max(0, Math.min(charLength(sourceText), omission.char_to)) });
    });
    try {
      return { ok: true, text: composeMarkedText(sourceText, annotations) };
    } catch (error) {
      return { ok: false, error: `Bogteksten kunne ikke gendannes: ${error.message}` };
    }
  }

  function init(data) {
    const shared = global.DAAReviewShared;
    const textarea = document.querySelector('[data-role="boundary-text"]');
    const gateStatus = document.querySelector('[data-role="gate-status"]');
    const saveStatus = document.querySelector('[data-role="save-status"]');
    const exportButton = document.querySelector('[data-action="export"]');
    const restoreButton = document.querySelector('[data-action="restore"]');
    const completeButton = document.querySelector('[data-action="complete-page"]');
    const progressNode = document.querySelector('[data-role="page-progress"]');
    const pageList = document.querySelector('[data-role="page-list"]');
    const storageKey = STORAGE_PREFIX + data.source.calamari_sha256;
    const stored = shared.readStoredDraft(global.localStorage, storageKey);
    const initialPageTexts = data.pages.map(page => page.initialText);
    const storedTexts = stored && Array.isArray(stored.page_texts)
      && stored.page_texts.length === data.pages.length
      && stored.page_texts.every(value => typeof value === 'string')
      ? stored.page_texts : null;
    const pageTexts = storedTexts ? storedTexts.slice() : initialPageTexts;
    let reviewedPages = reviewedPdfPages(
      data,
      stored && Array.isArray(stored.reviewed_pages)
        ? stored.reviewed_pages : data.completedPages,
    );
    let currentIndex = stored && Number.isInteger(stored.current_page)
      && stored.current_page >= 0 && stored.current_page < data.pages.length
      ? stored.current_page : 0;
    textarea.value = pageTexts[currentIndex];
    let timer = null;

    function renderPageControls(gate) {
      const progress = pageProgress(data, reviewedPages, currentIndex);
      progressNode.textContent = progress.counter;
      const reviewed = new Set(reviewedPages);
      pageList.innerHTML = progress.items.map((label, index) => (
        `<button type="button" data-page-index="${index}"`
        + `${index === currentIndex ? ' aria-current="page"' : ''}`
        + `>${label}</button>`
      )).join('');
      completeButton.textContent = reviewed.has(data.pages[currentIndex].pdfPage)
        ? 'Fjern mærket gennemgået' : 'Færdig med siden';
      completeButton.disabled = !gate.ok
        && !reviewed.has(data.pages[currentIndex].pdfPage);
    }

    function refresh() {
      pageTexts[currentIndex] = textarea.value;
      const gate = validatePageTexts(pageTexts, data);
      gateStatus.textContent = gate.message;
      gateStatus.dataset.gate = gate.ok ? 'ok' : 'error';
      exportButton.disabled = !gate.ok;
      renderPageControls(gate);
      const error = shared.writeStoredDraft(global.localStorage, storageKey, {
        schema_version: 2,
        page_texts: pageTexts,
        current_page: currentIndex,
        reviewed_pages: reviewedPages,
      });
      saveStatus.textContent = error || 'Gemt lokalt.';
      return gate;
    }

    textarea.addEventListener('input', () => {
      global.clearTimeout(timer);
      timer = global.setTimeout(refresh, 300);
    });
    exportButton.addEventListener('click', () => {
      pageTexts[currentIndex] = textarea.value;
      const exported = buildExportFromPages(pageTexts, data, null, reviewedPages);
      if (!exported.ok) {
        refresh();
        return;
      }
      shared.downloadJson(exported.value, '1939-graenseflade.json');
    });
    restoreButton.addEventListener('click', () => {
      pageTexts[currentIndex] = textarea.value;
      const restored = restoreBookText(pageTexts.join(''), data.sourceText);
      if (!restored.ok) {
        gateStatus.textContent = restored.error;
        gateStatus.dataset.gate = 'error';
        return;
      }
      const restoredParsed = parseMarkedText(restored.text, data.sourceText);
      const restoredPages = data.pages.map((page, index) => {
        const start = restoredParsed.viewOffsets.get(page.charFrom);
        const end = index + 1 < data.pages.length
          ? restoredParsed.viewOffsets.get(data.pages[index + 1].charFrom)
          : restored.text.length;
        return restored.text.slice(start, end);
      });
      restoredPages.forEach((text, index) => { pageTexts[index] = text; });
      textarea.value = pageTexts[currentIndex];
      refresh();
    });
    completeButton.addEventListener('click', () => {
      const gate = refresh();
      const result = togglePageCompletion(
        data, reviewedPages, currentIndex, gate.ok,
      );
      reviewedPages = result.reviewedPages;
      currentIndex = result.currentIndex;
      textarea.value = pageTexts[currentIndex];
      refresh();
    });
    pageList.addEventListener('click', event => {
      const button = event.target.closest('[data-page-index]');
      if (!button) return;
      pageTexts[currentIndex] = textarea.value;
      currentIndex = Number(button.dataset.pageIndex);
      textarea.value = pageTexts[currentIndex];
      refresh();
    });
    refresh();
  }

  global.DAABoundaryText = {
    parseMarkedText, composeMarkedText, buildExport, restoreBookText,
    validatePageTexts, buildExportFromPages, pageProgress, togglePageCompletion, init,
  };
}(typeof globalThis === 'undefined' ? this : globalThis));

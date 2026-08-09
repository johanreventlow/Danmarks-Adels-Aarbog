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

  function gateFor(bookText, sourceText) {
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
    const line = lineAt(sourceText, position);
    return { ok: false, line, message: `bogteksten er ændret ved linje ${line}` };
  }

  function parseMarkedText(markedText, sourceText) {
    const markers = [];
    const ocrNotes = [];
    const omissions = [];
    const book = [];
    let bookOffset = 0;
    let viewIndex = 0;
    let lineNumber = 1;
    let openOmission = null;

    function failure(message, line) {
      return { ok: false, line, error: `${message} ved linje ${line}` };
    }

    while (viewIndex < markedText.length) {
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

      let position = 0;
      while (position < rawLine.length) {
        const opening = rawLine.indexOf('[[', position);
        const closing = rawLine.indexOf(']]', position);
        if (closing !== -1 && (opening === -1 || closing < opening)) {
          return failure('uparret inline-tag', lineNumber);
        }
        if (opening === -1) {
          const tail = rawLine.slice(position);
          book.push(tail);
          bookOffset += charLength(tail);
          break;
        }
        const plain = rawLine.slice(position, opening);
        book.push(plain);
        bookOffset += charLength(plain);
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
    return { ok: true, bookText, markers, ocrNotes, omissions, gate: gateFor(bookText, sourceText) };
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
    const storageKey = STORAGE_PREFIX + data.source.calamari_sha256;
    const stored = shared.readStoredDraft(global.localStorage, storageKey);
    textarea.value = stored && typeof stored.marked_text === 'string'
      ? stored.marked_text : data.initialText;
    let timer = null;

    function refresh() {
      const parsed = parseMarkedText(textarea.value, data.sourceText);
      const gate = parsed.ok ? parsed.gate : {
        ok: false,
        message: parsed.error,
      };
      gateStatus.textContent = gate.message;
      gateStatus.dataset.gate = gate.ok ? 'ok' : 'error';
      exportButton.disabled = !gate.ok;
      const error = shared.writeStoredDraft(global.localStorage, storageKey, {
        schema_version: 1,
        marked_text: textarea.value,
      });
      saveStatus.textContent = error || 'Gemt lokalt.';
    }

    textarea.addEventListener('input', () => {
      global.clearTimeout(timer);
      timer = global.setTimeout(refresh, 300);
    });
    exportButton.addEventListener('click', () => {
      const exported = buildExport(textarea.value, data);
      if (!exported.ok) {
        refresh();
        return;
      }
      shared.downloadJson(exported.value, '1939-graenseflade.json');
    });
    restoreButton.addEventListener('click', () => {
      const restored = restoreBookText(textarea.value, data.sourceText);
      if (!restored.ok) {
        gateStatus.textContent = restored.error;
        gateStatus.dataset.gate = 'error';
        return;
      }
      textarea.value = restored.text;
      refresh();
    });
    refresh();
  }

  global.DAABoundaryText = {
    parseMarkedText, composeMarkedText, buildExport, restoreBookText, init,
  };
}(typeof globalThis === 'undefined' ? this : globalThis));

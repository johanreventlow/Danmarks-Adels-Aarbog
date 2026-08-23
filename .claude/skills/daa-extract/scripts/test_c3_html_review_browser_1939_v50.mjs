#!/usr/bin/env node

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { chromium } from "@playwright/test";


const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_SCRIPT = path.join(
  SCRIPT_DIR, "c3_html_review_test_fixtures.py");
const GENERATOR_SCRIPT = path.join(
  SCRIPT_DIR, "build_c3_html_review_1939_v50.py");

function runPython(args) {
  const result = spawnSync("/usr/bin/python3", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  assert.equal(result.status, 0, "synthetic Python command failed");
  assert.equal(result.stderr, "", "synthetic Python command wrote stderr");
  assert.equal(result.stdout.includes("Syntetisk"), false);
  assert.equal(result.stdout.includes("</script>"), false);
}

function decodeBase64Url(value) {
  return Buffer.from(value, "base64url");
}

function readSyntheticPayload(htmlPath) {
  const html = fs.readFileSync(htmlPath, "utf8");
  const match = html.match(/<div id="c3-payload" hidden>([A-Za-z0-9_-]+=*)<\/div>/);
  assert.ok(match, "synthetic HTML payload missing");
  return JSON.parse(decodeBase64Url(match[1]).toString("utf8"));
}

function replaceTokenBytes(source, slots, tokens) {
  let result = Buffer.from(source);
  const replacements = slots.map((slot, index) => ({
    start: slot.start,
    end: slot.end,
    token: Buffer.from(tokens[index], "utf8")
  })).sort((left, right) => right.start - left.start);
  for (const replacement of replacements) {
    result = Buffer.concat([
      result.subarray(0, replacement.start),
      replacement.token,
      result.subarray(replacement.end)
    ]);
  }
  return result;
}

async function selectAction(control, value) {
  await control.locator("select.choice").nth(0).selectOption(value);
}

async function assertHidden(locator, hidden) {
  assert.equal(await locator.isHidden(), hidden);
}

async function downloadTo(page, button, destination) {
  const pending = page.waitForEvent("download");
  await button.click();
  const download = await pending;
  assert.equal(download.suggestedFilename(), "c3-afgoerelser-redigeret.txt");
  await download.saveAs(destination);
  await page.locator("output.digest").waitFor({state: "visible"});
  return fs.readFileSync(destination);
}

async function main() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "c3-html-browser-"));
  let browser;
  try {
    runPython([FIXTURE_SCRIPT, "--output-dir", tempDir]);
    const selectionPath = path.join(tempDir, "selection.json");
    const statePath = path.join(tempDir, "state.json");
    const reviewPath = path.join(tempDir, "review.txt");
    const htmlPath = path.join(tempDir, "review.html");
    runPython([
      GENERATOR_SCRIPT,
      "--selection", selectionPath,
      "--state", statePath,
      "--review", reviewPath,
      "--output", htmlPath
    ]);

    const baseline = fs.readFileSync(reviewPath);
    const payload = readSyntheticPayload(htmlPath);
    assert.equal(payload.cases.length, 7);
    assert.equal(payload.slots.length, 15);

    browser = await chromium.launch({headless: true});
    const context = await browser.newContext({acceptDownloads: true});
    await context.addInitScript(() => {
      const accesses = [];
      const installed = [];
      Object.defineProperty(globalThis, "__C3_TEST_API_ACCESSES__", {
        value: accesses,
        configurable: false
      });
      Object.defineProperty(globalThis, "__C3_TEST_AUDIT_INSTALLED__", {
        value: installed,
        configurable: false
      });
      const auditProperty = (object, name) => {
        let owner = object;
        while (owner && !Object.prototype.hasOwnProperty.call(owner, name)) {
          owner = Object.getPrototypeOf(owner);
        }
        const descriptor = owner
          ? Object.getOwnPropertyDescriptor(owner, name)
          : undefined;
        if (!descriptor || !descriptor.configurable || !descriptor.get) {
          return;
        }
        const replacement = {
          ...descriptor,
          get() {
            accesses.push(`${name}:read`);
            return descriptor.get.call(this);
          }
        };
        if (descriptor.set) {
          replacement.set = function(value) {
            accesses.push(`${name}:write`);
            return descriptor.set.call(this, value);
          };
        }
        Object.defineProperty(owner, name, replacement);
        installed.push({name, reads: true, writes: Boolean(descriptor.set)});
      };
      auditProperty(globalThis, "localStorage");
      auditProperty(globalThis, "sessionStorage");
      auditProperty(globalThis, "indexedDB");
      auditProperty(Document.prototype, "cookie");
    });
    const page = await context.newPage();
    const requestProtocols = [];
    await page.route("**/*", async route => {
      const protocol = new URL(route.request().url()).protocol;
      requestProtocols.push(protocol);
      if (protocol !== "file:" && protocol !== "data:") {
        await route.abort("blockedbyclient");
        return;
      }
      await route.continue();
    });
    await page.goto(pathToFileURL(htmlPath).href, {waitUntil: "load"});

    const cards = page.locator("section.case-card");
    const controls = page.locator("section.decision-control");
    const navButtons = page.locator("nav.case-navigation button");
    assert.equal(await cards.count(), 7);
    assert.equal(await controls.count(), 15);
    assert.equal(await navButtons.count(), 7);
    assert.equal(await page.locator("strong.position").textContent(), "1 af 7");
    assert.equal(
      await page.locator("span.counts").textContent(),
      "2 afklarede · 13 uafklarede");

    await navButtons.nth(3).click();
    assert.equal(await page.locator("strong.position").textContent(), "4 af 7");
    assert.equal(await cards.nth(3).isVisible(), true);
    await page.getByRole("button", {name: "Forrige"}).click();
    assert.equal(await page.locator("strong.position").textContent(), "3 af 7");
    await page.getByRole("button", {name: "Næste"}).click();
    assert.equal(await page.locator("strong.position").textContent(), "4 af 7");
    await navButtons.nth(0).click();

    const defaultTokens = await page.locator("code.exact-token").allTextContents();
    assert.deepEqual(
      defaultTokens,
      payload.slots.map(slot => slot.default_token));
    assert.deepEqual(defaultTokens.slice(-3), [
      "UAFKLARET", "TIL 1017", "TIL 1021"]);

    await navButtons.nth(6).click();
    const specialIdentity = controls.nth(12);
    await selectAction(specialIdentity, "SAMME");
    assert.equal(
      await specialIdentity.locator("code.exact-token").textContent(),
      "SAMME 1021 1017");
    const specialTokens = await page.locator("code.exact-token").allTextContents();
    const expectedSpecial = replaceTokenBytes(baseline, payload.slots, specialTokens);
    const specialPath = path.join(tempDir, "special-same.txt");
    const specialDownload = await downloadTo(
      page, page.locator("button.download"), specialPath);
    assert.deepEqual(specialDownload, expectedSpecial);
    const specialSlot = payload.slots[12];
    assert.equal(
      specialDownload.subarray(
        specialSlot.start,
        specialSlot.start + Buffer.byteLength("SAMME 1021 1017")
      ).toString("utf8"),
      "SAMME 1021 1017");
    await page.reload({waitUntil: "load"});

    const firstIdentity = controls.nth(0);
    const identityDependent = firstIdentity.locator("div.dependent");
    await assertHidden(identityDependent, true);
    await selectAction(firstIdentity, "FORSKELLIGE");
    await assertHidden(identityDependent, true);
    await selectAction(firstIdentity, "SAMME");
    await assertHidden(identityDependent, false);
    await page.setViewportSize({width: 320, height: 900});
    const mobileMetrics = await page.evaluate(() => {
      const clientWidth = document.documentElement.clientWidth;
      return {
        clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
        overflowing: Array.from(document.querySelectorAll("body *"))
          .map(element => ({
            tag: element.tagName,
            className: element.className,
            right: Math.ceil(element.getBoundingClientRect().right),
            scrollWidth: element.scrollWidth,
            clientWidth: element.clientWidth
          }))
          .filter(item => item.right > clientWidth || item.scrollWidth > item.clientWidth)
      };
    });
    assert.equal(mobileMetrics.clientWidth, 320);
    assert.equal(
      mobileMetrics.scrollWidth <= mobileMetrics.clientWidth,
      true,
      JSON.stringify(mobileMetrics));
    const mobileControlBox = await firstIdentity.boundingBox();
    assert.ok(mobileControlBox);
    assert.equal(mobileControlBox.x >= 0, true);
    assert.equal(mobileControlBox.x + mobileControlBox.width <= 320, true);
    for (const element of await firstIdentity.locator(
      "select.choice, button.swap-direction").all()) {
      const box = await element.boundingBox();
      assert.ok(box);
      assert.equal(box.x >= 0, true);
      assert.equal(box.x + box.width <= 320, true);
    }
    const alias = firstIdentity.locator("select.choice").nth(1);
    const canonical = firstIdentity.locator("select.choice").nth(2);
    assert.notEqual(await alias.inputValue(), await canonical.inputValue());
    assert.equal(
      await alias.locator(`option[value="${await canonical.inputValue()}"]`).isDisabled(),
      true);
    assert.equal(
      await canonical.locator(`option[value="${await alias.inputValue()}"]`).isDisabled(),
      true);

    const originalAlias = await alias.inputValue();
    const originalCanonical = await canonical.inputValue();
    const swap = firstIdentity.getByRole("button", {name: "Byt retning"});
    await swap.click();
    assert.equal(await alias.inputValue(), originalCanonical);
    assert.equal(await canonical.inputValue(), originalAlias);
    assert.equal(
      await firstIdentity.locator("code.exact-token").textContent(),
      `SAMME ${originalCanonical} ${originalAlias}`);

    const firstRecord = controls.nth(1);
    const recordDependents = firstRecord.locator("div.dependent");
    await assertHidden(recordDependents.nth(0), true);
    await assertHidden(recordDependents.nth(1), true);
    await selectAction(firstRecord, "TIL");
    await assertHidden(recordDependents.nth(0), false);
    await assertHidden(recordDependents.nth(1), true);
    const recordPerson = firstRecord.locator("select.choice").nth(1);
    const secondPerson = await recordPerson.locator("option").nth(1).getAttribute("value");
    await recordPerson.selectOption(secondPerson);
    assert.equal(
      await firstRecord.locator("code.exact-token").textContent(),
      `TIL ${secondPerson}`);
    await selectAction(firstRecord, "INGEN_PUBLIKATION");
    await assertHidden(recordDependents.nth(0), true);
    await assertHidden(recordDependents.nth(1), true);
    assert.equal(
      await firstRecord.locator("code.exact-token").textContent(),
      "INGEN_PUBLIKATION");
    await selectAction(firstRecord, "REVISION");
    await assertHidden(recordDependents.nth(0), true);
    await assertHidden(recordDependents.nth(1), false);
    const revision = firstRecord.locator("select.choice").nth(2);
    for (const kind of ["split_into", "merged_from", "replaced_by"]) {
      await revision.selectOption(kind);
      assert.equal(
        await firstRecord.locator("code.exact-token").textContent(),
        `REVISION ${kind}`);
    }
    await selectAction(firstRecord, "TIL");
    await recordPerson.selectOption(secondPerson);

    const firstComparison = cards.nth(0).locator("section.comparison");
    assert.equal(await firstComparison.getByRole("heading", {
      name: "Kilderecord R03"
    }).count(), 1);
    assert.equal(await firstComparison.locator("article.source-record").count(), 1);
    assert.equal(await firstComparison.locator("article.candidate-card").count(), 2);
    assert.equal(
      await firstComparison.locator("p.source-text").textContent(),
      "Syntetisk kildetekst ÆØÅ R03");
    assert.equal(await firstComparison.locator("article.source-record").getByText(
      "Side: 603–604", {exact: true}
    ).count(), 1);
    const candidateTexts = await firstComparison.locator(
      "p.candidate-text").allTextContents();
    assert.equal(candidateTexts.length, 2);
    assert.equal(candidateTexts.some(text => text.includes(
      "</script><img src=x onerror=globalThis.__C3_PWNED__=1>")), true);
    assert.equal(await firstComparison.getByText("Person-ID 1101", {
      exact: true
    }).count(), 1);
    assert.equal(await firstComparison.locator("article.candidate-card").getByText("Side: 500", {
      exact: true
    }).count(), 2);
    assert.equal(await firstComparison.getByText("Eksisterende person", {
      exact: true
    }).count(), 1);
    assert.equal(await firstComparison.getByText("Kladdeperson", {
      exact: true
    }).count(), 1);
    assert.equal(await firstComparison.getByText("Offentlig", {
      exact: true
    }).count(), 2);
    assert.equal(await firstComparison.getByText(
      "Narrativ 6101 · side 500 · publiceret binding", {exact: true}
    ).count(), 1);
    assert.equal(await firstComparison.getByText(
      "Narrativ 6102 · side 500 · ingen recordbinding", {exact: true}
    ).count(), 1);
    assert.equal(await firstComparison.getByText(
      "Person 1101 er registreret som samme person som person 9101.",
      {exact: true}
    ).count(), 1);
    assert.equal(await firstComparison.getByText(
      "Person 1101 er registreret som forskellig fra person 9102.",
      {exact: true}
    ).count(), 1);
    assert.equal(await firstComparison.getByText(
      "Advarsel: Person 1101 og person 1102 er partnere i familie 77.",
      {exact: true}
    ).count(), 1);
    const visibleComparisonText = await firstComparison.textContent();
    for (const rawSurface of [
      "{", "}", '"records"', '"persons"', "identity_edges",
      "partner_conflicts", "verbatim_text", "new_record_key"
    ]) {
      assert.equal(visibleComparisonText.includes(rawSurface), false);
    }
    assert.equal(await page.evaluate(() => globalThis.__C3_PWNED__), undefined);

    const selectNames = await page.locator("select.choice").evaluateAll(selects =>
      selects.map(select => select.getAttribute("aria-label") || ""));
    assert.equal(selectNames.length > 0, true);
    assert.equal(selectNames.every(name => name.trim().length > 0), true);
    assert.equal(new Set(selectNames).size, selectNames.length);
    const decisionIds = payload.cases.flatMap(caseData =>
      caseData.controls.map(control => control.decision_id));
    assert.equal(selectNames.every(name =>
      decisionIds.some(decisionId => name.includes(decisionId))), true);

    await navButtons.nth(2).click();
    assert.equal(await cards.nth(2).locator("article.source-record").getByText(
      "Side: Ikke registreret", {exact: true}
    ).count(), 1);
    await navButtons.nth(0).click();

    await navButtons.nth(6).click();
    const specialComparison = cards.nth(6).locator("section.comparison");
    assert.deepEqual(
      await specialComparison.locator("article.source-record h3").allTextContents(),
      ["Kilderecord R15", "Kilderecord R40"]);
    await navButtons.nth(0).click();

    const downloadButton = page.getByRole("button", {
      name: "Download c3-afgoerelser-redigeret.txt"
    });
    await page.evaluate(() => {
      const control = document.querySelector("section.decision-control");
      const selects = control.querySelectorAll("select.choice");
      selects[2].value = selects[1].value;
      selects[2].dispatchEvent(new Event("change", {bubbles: true}));
    });
    assert.equal(await downloadButton.isDisabled(), true);
    await page.evaluate(() => {
      document.querySelector("button.download").disabled = false;
    });
    let rejectedDownloads = 0;
    const rejectCounter = () => { rejectedDownloads += 1; };
    page.on("download", rejectCounter);
    await downloadButton.click();
    await page.locator("output.digest").waitFor({state: "visible"});
    assert.equal(
      await page.locator("output.digest").textContent(),
      "Download afvist: et valg er ugyldigt.");
    assert.equal(rejectedDownloads, 0);
    page.off("download", rejectCounter);

    await page.reload({waitUntil: "load"});
    await selectAction(firstIdentity, "SAMME");
    await swap.click();
    await selectAction(firstRecord, "TIL");
    await recordPerson.selectOption(secondPerson);
    assert.equal(await downloadButton.isEnabled(), true);
    assert.equal(
      await page.locator("span.counts").textContent(),
      "4 afklarede · 11 uafklarede");

    await page.reload({waitUntil: "load"});
    assert.deepEqual(
      await page.locator("code.exact-token").allTextContents(),
      payload.slots.map(slot => slot.default_token));
    assert.equal(
      await page.locator("span.counts").textContent(),
      "2 afklarede · 13 uafklarede");

    const unchangedPath = path.join(tempDir, "unchanged.txt");
    const unchanged = await downloadTo(
      page, page.locator("button.download"), unchangedPath);
    assert.deepEqual(unchanged, baseline);
    const unchangedHash = crypto.createHash("sha256").update(unchanged).digest("hex");
    assert.equal(
      await page.locator("output.digest").textContent(),
      `SHA-256: ${unchangedHash}`);

    const reloadedControls = page.locator("section.decision-control");
    const editedIdentity = reloadedControls.nth(0);
    await selectAction(editedIdentity, "SAMME");
    await editedIdentity.getByRole("button", {name: "Byt retning"}).click();
    const editedRecord = reloadedControls.nth(1);
    await selectAction(editedRecord, "TIL");
    const editedPerson = editedRecord.locator("select.choice").nth(1);
    await editedPerson.selectOption(
      await editedPerson.locator("option").nth(1).getAttribute("value"));
    const editedTokens = await page.locator("code.exact-token").allTextContents();
    assert.notEqual(editedTokens[0].length, payload.slots[0].default_token.length);
    const expectedEdited = replaceTokenBytes(baseline, payload.slots, editedTokens);
    const editedPath = path.join(tempDir, "edited.txt");
    const edited = await downloadTo(
      page, page.locator("button.download"), editedPath);
    assert.deepEqual(edited, expectedEdited);
    const editedHash = crypto.createHash("sha256").update(edited).digest("hex");
    assert.equal(
      await page.locator("output.digest").textContent(),
      `SHA-256: ${editedHash}`);

    for (let index = 0; index < payload.slots.length; index += 1) {
      const slot = payload.slots[index];
      const expectedToken = Buffer.from(editedTokens[index], "utf8");
      assert.equal(
        edited.includes(expectedToken),
        true,
        `edited token ${index} missing`);
      assert.equal(slot.start < slot.end, true);
    }

    assert.deepEqual(
      await page.evaluate(() => globalThis.__C3_TEST_API_ACCESSES__), []);
    assert.deepEqual(
      (await page.evaluate(() => globalThis.__C3_TEST_AUDIT_INSTALLED__))
        .sort((left, right) => left.name.localeCompare(right.name)),
      [
        {name: "cookie", reads: true, writes: true},
        {name: "indexedDB", reads: true, writes: false},
        {name: "localStorage", reads: true, writes: false},
        {name: "sessionStorage", reads: true, writes: false}
      ]);
    assert.deepEqual(await context.cookies(), []);
    assert.equal(requestProtocols.length >= 3, true);
    assert.equal(
      requestProtocols.every(protocol => protocol === "file:" || protocol === "data:"),
      true);
    assert.deepEqual(
      fs.readdirSync(tempDir).sort(),
      ["edited.txt", "review.html", "review.txt", "selection.json", "special-same.txt", "state.json", "unchanged.txt"]);

    await context.close();
    await browser.close();
    browser = undefined;
    process.stdout.write("C3_HTML_BROWSER_OK sager=7 beslutninger=15 downloads=3\n");
  } finally {
    if (browser) {
      await browser.close();
    }
    fs.rmSync(tempDir, {recursive: true, force: true});
  }
}

async function mainApply() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "c3-html-apply-browser-"));
  let browser;
  try {
    const manifestPath = path.join(tempDir, "manifest.json");
    const htmlPath = path.join(tempDir, "apply.html");
    runPython(["-c",
      "import importlib.util, pathlib\n" +
      "spec = importlib.util.spec_from_file_location('fx', " +
      JSON.stringify(FIXTURE_SCRIPT) + ")\n" +
      "m = importlib.util.module_from_spec(spec)\n" +
      "spec.loader.exec_module(m)\n" +
      "m.write_apply_fixture(pathlib.Path(" + JSON.stringify(tempDir) + "))\n"
    ]);
    runPython([
      GENERATOR_SCRIPT,
      "--mode", "apply",
      "--manifest", manifestPath,
      "--output", htmlPath
    ]);

    const manifestDocument = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    const expectedElementIds = manifestDocument.cases
      .flatMap(caseRow => caseRow.events)
      .filter(event => event.action === "assign")
      .map(event => event.element_id)
      .sort();

    const html = fs.readFileSync(htmlPath, "utf8");
    const match = html.match(
      /<div id="c3-apply-payload" hidden>([A-Za-z0-9_-]+=*)<\/div>/);
    assert.ok(match, "synthetic apply HTML payload missing");
    const payload = JSON.parse(decodeBase64Url(match[1]).toString("utf8"));
    assert.equal(payload.cards.length, 4);
    assert.equal(payload.slots.length, 4);
    assert.deepEqual(
      payload.cards.map(card => card.element_id),
      payload.slots.map(slot => slot.element_id));
    assert.deepEqual(
      payload.slots.map(slot => slot.element_id), expectedElementIds);

    const sheetMatch = html.match(
      /<div id="c3-apply-sheet" hidden>([A-Za-z0-9_-]+=*)<\/div>/);
    assert.ok(sheetMatch, "synthetic apply HTML sheet missing");
    const baseline = decodeBase64Url(sheetMatch[1]);

    browser = await chromium.launch({headless: true});
    const context = await browser.newContext({acceptDownloads: true});
    await context.addInitScript(() => {
      const accesses = [];
      Object.defineProperty(globalThis, "__C3_APPLY_TEST_API_ACCESSES__", {
        value: accesses,
        configurable: false
      });
      const auditProperty = (object, name) => {
        let owner = object;
        while (owner && !Object.prototype.hasOwnProperty.call(owner, name)) {
          owner = Object.getPrototypeOf(owner);
        }
        const descriptor = owner
          ? Object.getOwnPropertyDescriptor(owner, name)
          : undefined;
        if (!descriptor || !descriptor.configurable || !descriptor.get) {
          return;
        }
        const replacement = {
          ...descriptor,
          get() {
            accesses.push(`${name}:read`);
            return descriptor.get.call(this);
          }
        };
        if (descriptor.set) {
          replacement.set = function(value) {
            accesses.push(`${name}:write`);
            return descriptor.set.call(this, value);
          };
        }
        Object.defineProperty(owner, name, replacement);
      };
      auditProperty(globalThis, "localStorage");
      auditProperty(globalThis, "sessionStorage");
      auditProperty(globalThis, "indexedDB");
      auditProperty(Document.prototype, "cookie");
    });
    const page = await context.newPage();
    const requestProtocols = [];
    await page.route("**/*", async route => {
      const protocol = new URL(route.request().url()).protocol;
      requestProtocols.push(protocol);
      if (protocol !== "file:" && protocol !== "data:") {
        await route.abort("blockedbyclient");
        return;
      }
      await route.continue();
    });
    await page.goto(pathToFileURL(htmlPath).href, {waitUntil: "load"});

    const cards = page.locator("section.case-card");
    const controls = page.locator("section.decision-control");
    assert.equal(await cards.count(), 4);
    assert.equal(await controls.count(), 4);

    // Kortenes rækkefølge i DOM'et SKAL følge arkets linjerækkefølge
    // (payload.slots, allerede bekræftet lig payload.cards ovenfor) — en
    // menneskelig godkender, der ser "kort 3", skal se den samme sag som
    // "linje 3" i det downloadede ark.
    const cardHeadings = await cards.locator("h2").allTextContents();
    assert.deepEqual(
      cardHeadings,
      payload.cards.map((card, index) => `Tekst ${index + 1} af ${payload.cards.length}`));

    const selects = page.locator("select.choice");
    assert.equal(await selects.count(), 4);
    const selectNames = await selects.evaluateAll(nodes =>
      nodes.map(node => node.getAttribute("aria-label") || ""));
    assert.equal(new Set(selectNames).size, selectNames.length);
    assert.equal(
      selectNames.every(name => payload.cards.some(
        card => name.includes(card.element_id))),
      true);

    const attackText = await cards.first().locator("p.candidate-text").textContent();
    assert.equal(
      attackText.includes("</script><img src=x onerror=globalThis.__C3_APPLY_PWNED__=1>"),
      true);
    assert.equal(await page.evaluate(() => globalThis.__C3_APPLY_PWNED__), undefined);
    const visibleText = await page.locator("main#c3-apply-app").textContent();
    for (const rawSurface of [
      "{", "}", '"cards"', '"slots"', "normalized_text", "before_state"
    ]) {
      assert.equal(visibleText.includes(rawSurface), false);
    }

    const downloadButton = page.getByRole("button", {
      name: "Download c3-apply-godkendelser.txt"
    });
    const unchangedPath = path.join(tempDir, "unchanged.txt");
    const unchangedPending = page.waitForEvent("download");
    await downloadButton.click();
    const unchangedDownload = await unchangedPending;
    assert.equal(
      unchangedDownload.suggestedFilename(), "c3-apply-godkendelser.txt");
    await unchangedDownload.saveAs(unchangedPath);
    await page.locator("output.digest").waitFor({state: "visible"});
    const unchanged = fs.readFileSync(unchangedPath);
    assert.deepEqual(unchanged, baseline);
    const unchangedHash = crypto.createHash("sha256").update(unchanged).digest("hex");
    assert.equal(
      await page.locator("output.digest").textContent(),
      `SHA-256: ${unchangedHash}`);

    for (let index = 0; index < await selects.count(); index += 1) {
      await selects.nth(index).selectOption("GODKENDT");
    }
    assert.equal(
      await page.locator("span.counts").textContent(),
      "4 godkendt · 0 uafklaret");
    const tokens = await page.locator("code.exact-token").allTextContents();
    assert.deepEqual(tokens, new Array(4).fill("GODKENDT"));

    const approvedPath = path.join(tempDir, "approved.txt");
    const approvedPending = page.waitForEvent("download");
    await downloadButton.click();
    const approvedDownload = await approvedPending;
    await approvedDownload.saveAs(approvedPath);
    await page.locator("output.digest").waitFor({state: "visible"});
    const approved = fs.readFileSync(approvedPath);
    assert.notDeepEqual(approved, baseline);
    assert.notEqual(approved.length, baseline.length);
    const approvedText = approved.toString("utf8");
    const approvedLines = approvedText.split("\n").filter(line => line.length);
    assert.equal(
      approvedLines.filter(line => line.startsWith("[GODKENDT]")).length, 4);
    for (const slot of payload.slots) {
      assert.equal(
        approvedText.includes(`[GODKENDT] approve:${slot.element_id}`),
        true);
    }
    const approvedHash = crypto.createHash("sha256").update(approved).digest("hex");
    assert.equal(
      await page.locator("output.digest").textContent(),
      `SHA-256: ${approvedHash}`);

    await page.setViewportSize({width: 320, height: 900});
    const mobileMetrics = await page.evaluate(() => {
      const clientWidth = document.documentElement.clientWidth;
      return {
        clientWidth,
        scrollWidth: document.documentElement.scrollWidth
      };
    });
    assert.equal(mobileMetrics.clientWidth, 320);
    assert.equal(mobileMetrics.scrollWidth <= mobileMetrics.clientWidth, true);
    const firstControlBox = await controls.first().boundingBox();
    assert.ok(firstControlBox);
    assert.equal(firstControlBox.x >= 0, true);
    assert.equal(firstControlBox.x + firstControlBox.width <= 320, true);

    assert.deepEqual(
      await page.evaluate(() => globalThis.__C3_APPLY_TEST_API_ACCESSES__), []);
    assert.deepEqual(await context.cookies(), []);
    // Observed exactly one request for this page: the file: navigation
    // itself (no favicon probe, unlike the review-mode page above). The
    // >= 1 floor keeps the assertion meaningful (a network egress would
    // still be caught by the file:/data: check below) without hardcoding
    // a count that depends on browser favicon-fetch behaviour.
    assert.equal(requestProtocols.length >= 1, true, JSON.stringify(requestProtocols));
    assert.equal(
      requestProtocols.every(protocol => protocol === "file:" || protocol === "data:"),
      true);
    assert.deepEqual(
      fs.readdirSync(tempDir).sort(),
      ["apply.html", "approved.txt", "manifest.json", "unchanged.txt"]);

    await context.close();
    await browser.close();
    browser = undefined;
    process.stdout.write("C3_HTML_APPLY_BROWSER_OK beslutninger=4 downloads=2\n");
  } finally {
    if (browser) {
      await browser.close();
    }
    fs.rmSync(tempDir, {recursive: true, force: true});
  }
}

main()
  .then(() => mainApply())
  .catch(error => {
    process.stderr.write(`C3_HTML_BROWSER_TEST_FAILED ${error.stack}\n`);
    process.exitCode = 1;
  });

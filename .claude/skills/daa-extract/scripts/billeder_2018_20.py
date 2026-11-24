"""Udtræk portrætter og billedtekster fra særudgaven af DAA 2018-20 til et manifest.

Spec: docs/superpowers/specs/2026-11-24-billeder-2018-20-design.md (trin 1).
Plan: docs/superpowers/plans/2026-11-24-billeder-2018-20.md (Task 1).

Brug (fra repo-roden):
    python3 .claude/skills/daa-extract/scripts/billeder_2018_20.py \
        "Dansk Adels Aarbog - Reventlow - Særudgave.pdf" work_2018_saerudgave/billeder

Ud-mappen er gitignoreret og må aldrig committes. Scriptet læser kun den publicerede bog; det slår ingen
personer op (det gør R/billeder-2018-20-load.R).
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FRA_SIDE, TIL_SIDE = 119, 369

REF = re.compile(r"\(([IVX]+|\d+)\s*,\s*(\d+)\)")
AARSPAEND = re.compile(r"(\d{4})\s*-\s*(\d{4})")
FOEDT_AAR = re.compile(r"født (\d{4})")
# Kunstnerlinje: »Malet ca. 1823 af …«, »Tegning i farvet kridt ca. 1780 af …«, »Litografi fra 1870’erne (?) af …«.
KUNSTNER = re.compile(r"^(Malet|Tegnet|Tegning|Litografi|Grafisk tryk|Radering|Raderet|Kobberstik|Stik|Skitsearbejde|"
                      r"Skitse|Pastel|Akvarel|Miniature)\b(.*?)\s*(?:\b(?:formentlig|sandsynligvis|muligvis)\s+)?\baf\s+(.+)$")
DATERING = re.compile(r"(?:ca\.\s*)?\d{4}(?:’erne)?(?:\s*(?:eller|-)\s*\d{4})?(?:\s*\(\?\))?")
FOTO = re.compile(r"^Foto(?:graferet)?(?: af|:)\s*(.+)$")
SIDEFOD_DATO = re.compile(r"^\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}\.\d{2}$")

# Størrelsestrin som web/src/data/mediaUpload.ts (TIER_SPECS); large er originalen.
TRIN = {"thumb": (500, 70), "medium": (1100, 78)}


def _linjer(tekst: str) -> list[str]:
    ud = []
    for linje in tekst.splitlines():
        s = " ".join(linje.split())
        if not s or "indd" in s or s.isdigit() or SIDEFOD_DATO.match(s):
            continue
        ud.append(s)
    return ud


def parse_billedtekst(tekst: str) -> dict:
    """Fortolker én sides billedtekst (pdftotext -layout) til felter i manifestet."""
    kunstner = datering = None
    slags = "portræt"
    rest = []
    for linje in _linjer(tekst):
        m = KUNSTNER.match(linje)
        if m:
            d = DATERING.search(m.group(2))
            datering, kunstner = (d.group(0) if d else None), m.group(3)
            if m.group(1) == "Malet":
                slags = "maleri"
            continue
        m = FOTO.match(linje)
        if m:
            kunstner, slags = m.group(1), "foto"
            continue
        rest.append(linje)

    fuld = " ".join(rest)
    foer, gift, efter = fuld.partition("Gift med")
    refs_foer = [[linje, int(nr)] for linje, nr in REF.findall(foer)]
    anker_match = REF.search(efter) if gift else None
    # Tekst efter personens egen henvisning eller efter ægtefællens anker (»og hustru …«, »På billedet ses …«) kan
    # nævne flere afbildede: så skal billedet gennemgås, ellers kobles det kun til den ene (final review, kritisk fund).
    sidste_ref = list(REF.finditer(foer))
    efter_ref = foer[sidste_ref[-1].end():].strip() if sidste_ref else ""
    efter_anker = efter[anker_match.end():].strip() if anker_match else ""

    if "fra venstre" in fuld.lower():
        klasse = "gruppe"
        refs_foer = []
        for linje, nr in REF.findall(fuld):
            if [linje, int(nr)] not in refs_foer:
                refs_foer.append([linje, int(nr)])
    elif len(refs_foer) > 1:
        klasse = "flere"
    elif len(refs_foer) == 1:
        klasse = "egen"
    elif anker_match:
        klasse = "aegtefaelle"
    else:
        klasse = "uafklaret"

    anker = navn = aar = None
    if klasse == "aegtefaelle":
        anker = [anker_match.group(1), int(anker_match.group(2))]
        navn = rest[0] if rest else None
        spaend = AARSPAEND.search(foer)
        if spaend:
            aar = [int(spaend.group(1)), int(spaend.group(2))]
        else:
            foedt = FOEDT_AAR.search(foer)
            aar = [int(foedt.group(1)), None] if foedt else None

    ekstra = (klasse == "egen" and bool(efter_ref or efter_anker)) or (klasse == "aegtefaelle" and bool(efter_anker))
    return {
        "ekstra_tekst": ekstra,
        "titel": fuld,
        "kunstner": kunstner,
        "datering": datering,
        "slags": slags,
        "klasse": klasse,
        "refs": refs_foer,
        "aegtefaelle_anker": anker,
        "aegtefaelle_navn": navn,
        "aegtefaelle_aar": aar,
    }


def vaelg_billedtekst(sidetekst: str, naeste_sidetekst: str | None, naeste_har_billede: bool) -> str:
    """Et opslag har billedet på venstre side og billedteksten på højre: er billedsiden uden tekst, og har næste side
    intet billede, er næste sides tekst billedteksten."""
    if _linjer(sidetekst) or naeste_sidetekst is None or naeste_har_billede:
        return sidetekst
    return naeste_sidetekst


def lav_varianter(kilde: Path, maske: Path | None, maal: Path, noegle: str) -> dict:
    """Large = originalens bytes (eller fladet på hvid, hvis billedet har en alfamaske); thumb/medium nedskaleres,
    aldrig op."""
    from PIL import Image

    maal = Path(maal)
    filer = {trin: f"{noegle}-{trin}.jpg" for trin in ("large", "medium", "thumb")}
    large = maal / filer["large"]
    if maske is None:
        if Path(kilde).resolve() != large.resolve():
            shutil.copyfile(kilde, large)
    else:
        with Image.open(kilde) as billede, Image.open(maske) as m:
            rgb = billede.convert("RGB")
            hvid = Image.new("RGB", rgb.size, (255, 255, 255))
            alfa = m.convert("L").resize(rgb.size)
            Image.composite(rgb, hvid, alfa).save(large, "JPEG", quality=90)

    dims = {}
    with Image.open(large) as billede:
        rgb = billede.convert("RGB")
        bredde, hoejde = rgb.size
        dims["large"] = [bredde, hoejde]
        for trin, (maks, kvalitet) in TRIN.items():
            b = min(maks, bredde)
            h = max(1, round(hoejde * b / bredde))
            ny = rgb if (b, h) == (bredde, hoejde) else rgb.resize((b, h), Image.LANCZOS)
            ny.save(maal / filer[trin], "JPEG", quality=kvalitet)
            dims[trin] = [b, h]

    data = large.read_bytes()
    return {
        "filer": filer,
        "dims": dims,
        "bytes": {trin: (maal / fil).stat().st_size for trin, fil in filer.items()},
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def _billedliste(pdf: Path, fra: int = FRA_SIDE, til: int = TIL_SIDE) -> list[dict]:
    """`pdfimages -list` for portrætafsnittet: billeder med evt. tilhørende smask (rækken lige efter)."""
    ud = subprocess.run(["pdfimages", "-list", "-f", str(fra), "-l", str(til), str(pdf)],
                        capture_output=True, text=True, check=True).stdout
    billeder: list[dict] = []
    for linje in ud.splitlines()[2:]:
        felter = linje.split()
        if len(felter) < 3:
            continue
        side, num, typ = int(felter[0]), int(felter[1]), felter[2]
        if typ == "image":
            billeder.append({"side": side, "num": num, "maske_num": None})
        elif typ == "smask" and billeder and billeder[-1]["side"] == side:
            billeder[-1]["maske_num"] = num
    return billeder


def _sidetekst(pdf: Path, side: int) -> str:
    return subprocess.run(["pdftotext", "-f", str(side), "-l", str(side), "-layout", str(pdf), "-"],
                          capture_output=True, text=True, check=True).stdout


def byg_manifest(pdf: Path, ud: Path) -> dict:
    ud.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        prefix = Path(tmp) / "b"
        subprocess.run(["pdfimages", "-j", "-png", "-f", str(FRA_SIDE), "-l", str(TIL_SIDE), str(pdf), str(prefix)],
                       check=True)

        def fil(num: int) -> Path:
            hits = sorted(Path(tmp).glob(f"b-{num:03d}.*"))
            if len(hits) != 1:
                raise RuntimeError(f"Forventede én fil for billede {num}, fandt {len(hits)}")
            return hits[0]

        billeder = []
        nr_paa_side: dict[int, int] = {}
        liste = _billedliste(pdf)
        sider_med_billede = {b["side"] for b in liste}
        for b in liste:
            side = b["side"]
            nr_paa_side[side] = nr_paa_side.get(side, 0) + 1
            noegle = f"daa-2018-20-s{side:04d}-{nr_paa_side[side]}"
            naeste = side + 1
            naeste_har_billede = naeste in sider_med_billede or (
                naeste > TIL_SIDE and bool(_billedliste(pdf, naeste, naeste)))
            tekst = vaelg_billedtekst(_sidetekst(pdf, side), _sidetekst(pdf, naeste), naeste_har_billede)
            maske = fil(b["maske_num"]) if b["maske_num"] is not None else None
            post = {"noegle": noegle, "side": side, "billednr": nr_paa_side[side],
                    "billedtekst": "\n".join(_linjer(tekst))}
            post.update(lav_varianter(fil(b["num"]), maske, ud, noegle))
            post.update(parse_billedtekst(tekst))
            billeder.append(post)

    manifest = {"kilde_pdf": pdf.name, "sider": [FRA_SIDE, TIL_SIDE], "billeder": billeder}
    (ud / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    return manifest


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Brug: billeder_2018_20.py <pdf> <ud-mappe>", file=sys.stderr)
        return 2
    manifest = byg_manifest(Path(argv[0]), Path(argv[1]))
    klasser: dict[str, int] = {}
    for b in manifest["billeder"]:
        klasser[b["klasse"]] = klasser.get(b["klasse"], 0) + 1
    print(f"{len(manifest['billeder'])} billeder; klasser: {klasser}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

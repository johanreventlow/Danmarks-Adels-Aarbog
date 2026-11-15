"""Privat filskrivning ét sted (review 36, K10).

Pipelinens private filer (menneskeark, token-filer, manifester, SQL, runnerens
svar-cache) rummer persondata eller er hash-bundne godkendelsesgrundlag.  To
egenskaber gælder for dem alle:

* **0600 fra første byte.**  Filen oprettes med mode 0600; den rettes ikke
  bagefter med `chmod`, så den aldrig et øjeblik har umask'ens rettigheder.
* **Ingen symlinks.**  Et symlink på målstien kunne lede skrivningen ud af den
  private mappe; det afvises, og selve åbningen sker med `O_NOFOLLOW`.

Kalderen vælger bevidst mellem to semantikker:

* `write_private_new` — nægter en eksisterende fil.  Til render-trin, der skriver
  et udfyldbart menneskeark: et udfyldt ark må aldrig overskrives stille.
* `write_private_replace` — skriver til en tempfil i samme mappe, `fsync`, og
  erstatter målet atomisk med `os.replace`.  Til maskin-output, der må genskabes,
  og til runnerens cache: en afbrudt skrivning efterlader aldrig en trunkeret fil
  på det endelige navn.

Begge skriver præcis de bytes, kalderen giver (en `str` kodes som UTF-8 uden
newline-oversættelse): arkene er hash-bundne, så intet må re-serialiseres her.

`check_private_path` er flyttet hertil uændret fra ark-scriptene, hvor den lå i
tre ens kopier.  Den rejser `SheetError` med de samme koder som før.
"""
from __future__ import annotations

import os
import secrets
import stat
from pathlib import Path

from decision_sheet_core import SheetError

__all__ = ["PrivateIOError", "check_private_path", "write_private_new", "write_private_new_many",
           "write_private_replace"]


class PrivateIOError(SheetError):
    """Fejl ved privat skrivning.  Underklasse af `SheetError`, så ark-scriptenes
    eksisterende `except SheetError`-håndtering melder koden i stedet for at vælte."""


def check_private_path(path: Path, root: Path) -> Path:
    root_r = root.resolve()
    if path.is_symlink():
        raise SheetError("SHEET_PATH_SYMLINK")
    p = path.resolve()
    if root_r not in p.parents:
        raise SheetError("SHEET_PATH_NOT_PRIVATE")
    for parent in [p.parent, *p.parent.parents]:
        if (parent / ".git").exists():
            raise SheetError("SHEET_PATH_IN_GIT")
    return p


def _as_bytes(data: str | bytes) -> bytes:
    if isinstance(data, str):
        return data.encode("utf-8")
    if isinstance(data, (bytes, bytearray)):
        return bytes(data)
    raise TypeError("private_io skriver kun str eller bytes")


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def _refuse_symlink(path: Path, code: str) -> None:
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return
    if stat.S_ISLNK(info.st_mode):
        raise PrivateIOError(code)


def write_private_new(path, data: str | bytes, *, exists_code: str = "PRIVATE_OUT_EXISTS") -> None:
    """Opret en NY fil med mode 0600; en eksisterende fil (eller et symlink) nægtes.

    `exists_code` lader kalderen bevare sin egen, dokumenterede fejlkode
    (fx `KOE_OUT_EXISTS`)."""
    path = Path(path)
    payload = _as_bytes(data)
    # O_EXCL nægter også et dinglende symlink; O_NOFOLLOW er værn nummer to.
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        raise PrivateIOError(exists_code) from None
    try:
        _write_all(fd, payload)
        os.fsync(fd)
    except BaseException:
        os.close(fd)
        path.unlink(missing_ok=True)
        raise
    os.close(fd)


def write_private_new_many(items, *, exists_code: str = "PRIVATE_OUT_EXISTS") -> None:
    """Som `write_private_new` for filer, der hører sammen (ark + token, token + html).

    Alle stier tjekkes, FØR noget skrives: ellers kunne et nyt token ende ved siden
    af et gammelt, udfyldt ark.  Fejler en senere skrivning, fjernes de filer, dette
    kald selv nåede at oprette."""
    items = [(Path(p), d) for p, d in items]
    if any(os.path.lexists(p) for p, _ in items):
        raise PrivateIOError(exists_code)
    skrevet: list[Path] = []
    try:
        for p, d in items:
            write_private_new(p, d, exists_code=exists_code)
            skrevet.append(p)
    except BaseException:
        for p in skrevet:
            p.unlink(missing_ok=True)
        raise


def write_private_replace(path, data: str | bytes, *,
                          symlink_code: str = "PRIVATE_OUT_SYMLINK") -> None:
    """Skriv atomisk: tempfil (0600, `O_EXCL|O_NOFOLLOW`) i samme mappe, `fsync`,
    `os.replace`.  Et symlink på målstien nægtes — `os.replace` ville ellers
    erstatte det stille.  Ved fejl ryddes tempfilen, og målet er urørt."""
    path = Path(path)
    payload = _as_bytes(data)
    _refuse_symlink(path, symlink_code)
    # Punktum-præfiks og `.tmp`-endelse: tempfilen ligner aldrig et rigtigt output
    # (fx `*.json` i runnerens cache-mappe), hvis en afbrydelse efterlader den.  Det
    # tilfældige led gør, at en efterladt tempfil fra en tidligere kørsel med samme pid
    # ikke spærrer (O_EXCL).
    tmp = path.with_name(f".{path.name}.{os.getpid()}.{secrets.token_hex(4)}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        try:
            _write_all(fd, payload)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    try:
        dfd = os.open(path.parent, os.O_RDONLY)
    except OSError:
        return
    try:
        os.fsync(dfd)
    except OSError:
        pass
    finally:
        os.close(dfd)

#!/usr/bin/env python3
"""Task 0 (fuld personsletning), step 2: kør de 4 PostgreSQL-CI-jobs lokalt med spikens vagter slået til.

Brug:  python3 tests/sql/spike/ci_jobs_lokalt.py --variant {base,warn,enforce} --prefix <præfiks> --out <mappe>
                                                 [--jobs evidence-promotion-db,...]

- Kopierer de git-sporede filer (+ spikens filer) til <out>/tree. Arbejdsmapperne work*/ er gitignorerede og kommer
  aldrig med. Repo'et selv ændres ikke.
- warn/enforce: tests/sql/spike/person-purge-skelet.sql hægtes på SIDST i kopiens schema.sql OG db-migrations.sql.
  Så ligger vagterne der efter hver anvendelse af en af filerne, også midt i et job og i opgraderingsharnesses, der
  lægger den aktuelle db-migrations.sql oven på et gammelt skema (db-migrations.sql genskaber ellers de gamle kroppe
  af enforce_relation_evidence_target og validate_entity_description_subject). warn sætter spike.indstilling til
  'warn' (RAISE WARNING SPIKE_VAGT_BRUD i stedet for fejl), så hele inventaret kommer med.
- Hvert job oversættes fra .github/workflows/ci.yml (ruby's YAML → JSON). Alle databasenavne fra ci.yml og fra
  tests/ci/interpretation-proposal-db.sh får præfikset, så intet eksisterende navn rammes. Hvert trin køres med
  bash -eo pipefail som i GitHub Actions; et fejlet trin stopper IKKE jobbet (vi vil have hele inventaret), men
  noteres. Senere trin i samme job kan derfor fejle som følgefejl.
- Output: <out>/<job>/<nr>-<navn>.log og <out>/trin.tsv (variant, job, nr, navn, rc, sekunder).
- Scriptet sletter ingen databaser. Det skriver til sidst listen over databaser med præfikset til <out>/baser.txt.
"""
import argparse, json, os, re, shutil, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
JOBS = ["evidence-promotion-db", "interpretation-proposal-db", "writer-1939-v50-db", "narrative-record-contract-db"]
SPIKE_FILES = ["tests/sql/spike/person-purge-skelet.sql", "tests/sql/spike/person-purge-fixture.sql",
               "tests/sql/spike/ci_jobs_lokalt.py", "tests/sql/spike-person-purge-laase.sh"]


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, check=True, text=True, capture_output=True, **kw).stdout


def db_names(wf):
    names = set()
    for j in JOBS:
        job = wf["jobs"][j]
        for svc in job.get("services", {}).values():
            n = svc.get("env", {}).get("POSTGRES_DB")
            if n: names.add(n)
        if job.get("env", {}).get("PGDATABASE"): names.add(job["env"]["PGDATABASE"])
        for st in job["steps"]:
            env = st.get("env") or {}
            if isinstance(env, dict) and env.get("PGDATABASE"): names.add(env["PGDATABASE"])
            run = st.get("run", "")
            for m in re.finditer(r"\b(?:createdb|dropdb)(?:\s+--?[\w-]+(?:=\S+)?|\s+-[hUT]\s+\S+)*\s+\"?([A-Za-z][\w]*)", run):
                names.add(m.group(1))
            for m in re.finditer(r"\s-d\s+\"?([A-Za-z][\w]*)\"?", run):
                names.add(m.group(1))
            for m in re.finditer(r"bash tests/\S+\.sh\s+\"?([a-z][\w]*)\"?", run):
                names.add(m.group(1))
            for m in re.finditer(r'database="([a-z][\w]*?)_\$', run):
                names.add(m.group(1))
    names = {n for n in names if "_" in n}   # bash, schema, localhost o.l. er ikke basenavne
    return sorted(names, key=len, reverse=True)


def rename(text, names, prefix):
    if not names: return text
    pat = re.compile(r"(?<![A-Za-z0-9_\-/.])(" + "|".join(map(re.escape, names)) + r")(?![A-Za-z0-9])")
    return pat.sub(lambda m: prefix + m.group(1), text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", required=True, choices=["base", "warn", "enforce", "enforce_kendte"])
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", default=",".join(JOBS))
    a = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]*_ci_[a-z0-9_]*", a.prefix):
        sys.exit("præfikset skal matche [a-z][a-z0-9_]*_ci_… (R-racetesten kræver 'ci' i navnet)")
    out = os.path.abspath(a.out); tree = os.path.join(out, "tree")
    if os.path.exists(out): sys.exit(f"{out} findes allerede")
    os.makedirs(os.path.join(tree, "tmp"))
    existing = sh("psql -X -At -d postgres -c \"SELECT datname FROM pg_database\"").split()
    clash = [d for d in existing if d.startswith(a.prefix)]
    if clash: sys.exit(f"baser med præfikset findes allerede: {clash}")

    files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True).stdout.split(b"\0")
    for f in [x.decode() for x in files if x] + SPIKE_FILES:
        src = os.path.join(ROOT, f)
        if not os.path.isfile(src): continue
        dst = os.path.join(tree, f); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst)
    if a.variant != "base":
        skel = open(os.path.join(ROOT, "tests/sql/spike/person-purge-skelet.sql")).read()
        tail = "\n-- ==== SPIKE (Task 0): vagter hægtet på af ci_jobs_lokalt.py ====\n" + skel
        if a.variant == "enforce_kendte":
            # De 13 kendte klasse-a-steder fra warn-inventaret advarer kun; alt andet fejler som i enforce.
            tail += ("\nINSERT INTO spike.indstilling VALUES ('kendte','person:-99,person:1,person:-999904,"
                     "person:-999951,person:-999941,person:-999942,person:-999943,person:-153109,family:-621017,"
                     "fact:-1') ON CONFLICT (noegle) DO UPDATE SET vaerdi=excluded.vaerdi;\n")
        if a.variant == "warn":
            tail += "\nUPDATE spike.indstilling SET vaerdi='warn' WHERE noegle='vagt_mode';\n"
        tail += "\nRESET client_min_messages;\n"
        for f in ("schema.sql", "db-migrations.sql"):
            with open(os.path.join(tree, f), "a") as fh: fh.write(tail)

    wf = json.loads(sh(f"ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' {ROOT}/.github/workflows/ci.yml"))
    names = db_names(wf) + ["proposal_projection"]
    names = sorted(set(names), key=len, reverse=True)
    pfx = a.prefix + "_"
    p = os.path.join(tree, "tests/ci/interpretation-proposal-db.sh")
    txt = open(p).read()
    open(p, "w").write(rename(txt, ["proposal_projection"], pfx))
    with open(os.path.join(out, "navne.txt"), "w") as fh: fh.write("\n".join(names) + "\n")

    base_env = {k: v for k, v in os.environ.items() if not k.startswith("PG")}
    base_env.update(PGHOST="localhost", PGPORT="5432", PGUSER=os.environ.get("USER", ""), PGPASSWORD="lokal-trust-ignoreres",
                    GIT_DIR=sh(f"git -C {ROOT} rev-parse --absolute-git-dir").strip(), DAA_PYTHON="python3")
    res = open(os.path.join(out, "trin.tsv"), "a")
    for j in a.jobs.split(","):
        job = wf["jobs"][j]; jd = os.path.join(out, j); os.makedirs(jd)
        env = dict(base_env)
        for k, v in (job.get("env") or {}).items():
            if not k.startswith("PG"): env[k] = str(v)
        if (job.get("env") or {}).get("PGDATABASE"): env["PGDATABASE"] = pfx + job["env"]["PGDATABASE"]
        for svc in job.get("services", {}).values():
            n = svc.get("env", {}).get("POSTGRES_DB")
            if n: subprocess.run(["createdb", pfx + n], check=True, env=env)
        nr = 0
        for st in job["steps"]:
            if "run" not in st: continue
            nr += 1
            run = st["run"].replace("-h localhost -U postgres ", "").replace("/tmp/", tree + "/tmp/")
            run = rename(run, names, pfx)
            senv = dict(env)
            for k, v in (st.get("env") or {}).items():
                if k == "PGDATABASE": senv[k] = pfx + str(v)
                elif not k.startswith("PG"): senv[k] = str(v)
            name = st.get("name", run.splitlines()[0])[:80]
            sf = os.path.join(jd, f"{nr:02d}.sh"); open(sf, "w").write(run)
            log = os.path.join(jd, f"{nr:02d}.log")
            t0 = time.time()
            with open(log, "w") as lf:
                rc = subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", sf], cwd=tree, env=senv,
                                    stdout=lf, stderr=subprocess.STDOUT).returncode
            line = f"{a.variant}\t{j}\t{nr:02d}\t{name}\t{rc}\t{time.time()-t0:.0f}"
            res.write(line + "\n"); res.flush(); print(line, flush=True)
    dbs = [d for d in sh("psql -X -At -d postgres -c \"SELECT datname FROM pg_database\"").split() if d.startswith(a.prefix)]
    open(os.path.join(out, "baser.txt"), "w").write("\n".join(dbs) + "\n")
    print(f"FAERDIG {a.variant}: {len(dbs)} baser med præfikset {a.prefix}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Static Task 11 lock candidates, run from the repository root (no database).

TSV columns: function, location, direct lock tables, calls, DML/trigger edges,
FK KEY SHARE edges. Edges are conservative: branches, UPDATE OF columns and
WHEN predicates are not evaluated. This is review evidence, not a SQL parser
or a proof of deadlock freedom. Dynamic version DML is expanded explicitly.
"""
import pathlib
import re
from collections import defaultdict

IDENT = r'[a-zA-Z_][\w]*(?:\.[a-zA-Z_][\w]*)?'
EVENTS = r'INSERT|UPDATE|DELETE|TRUNCATE'
FOCUS = {'private.source_record', 'public.source', 'public.person_external_id',
         'private.source_persona', 'private.source_persona_identity', 'public.person',
         'public.family', 'public.family_member', 'public.change_set',
         'public.media', 'public.media_variant'}
EXTRA = {'_version_lock_row', '_version_upsert_row', '_version_delete_row', 'log_change',
         'enforce_relation_evidence_target', 'private.guard_fact_evidence_delete',
         'private.reject_evidence_mutation', 'private.reject_row_mutation',
         'private.guard_identity_mutation_snapshot', 'private.lock_reimport_writer'}


def relation(name):
    return name.lower() if '.' in name else 'public.' + name.lower()


def function(name):
    return name.lower().removeprefix('public.')


def scrub(sql, strings=False):
    # Preserve offsets and newlines; quoted comment markers are not comments.
    token = r"'(?:''|[^'])*'|--[^\n]*|/\*[\s\S]*?\*/"
    return re.sub(token, lambda m: (re.sub(r'[^\n]', ' ', m[0])
                  if strings or not m[0].startswith("'") else m[0]), sql)


def inventory(sql):
    sql = scrub(sql)
    functions = {}
    ddl = list(sql)
    pos = 0
    pattern = re.compile(r'CREATE(?: OR REPLACE)? FUNCTION\s+(' + IDENT + r')\s*\(', re.I)
    while m := pattern.search(sql, pos):
        delimiter = re.search(r'\bAS\s+(\$\w*\$)', sql[m.end():], re.I)
        if delimiter is None:
            raise ValueError('Function without dollar-quoted body: ' + m[1])
        start = m.end() + delimiter.end()
        end = sql.find(delimiter[1], start)
        if end < 0:
            raise ValueError('Unterminated function: ' + m[1])
        name = function(m[1])
        functions[name] = (sql.count('\n', 0, m.start()) + 1, sql[start:end])
        finish = end + len(delimiter[1])
        ddl[m.start():finish] = re.sub(r'[^\n]', ' ', sql[m.start():finish])
        pos = finish
    ddl = ''.join(ddl)
    code = scrub(ddl, strings=True)

    # CREATE TABLE (inline/composite FKs) and ALTER TABLE ADD ... REFERENCES.
    fks = defaultdict(set)
    cascades = defaultdict(set)
    tables = set()
    for m in re.finditer(r'\b(CREATE TABLE(?: IF NOT EXISTS)?|ALTER TABLE)\s+(' + IDENT + r')\b([^;]*);', code, re.I):
        child = relation(m[2])
        tables.add(child)
        refs = list(re.finditer(r'\bREFERENCES\s+(' + IDENT + r')\s*\([^)]*\)', m[3], re.I))
        for i, ref in enumerate(refs):
            parent = relation(ref[1])
            fks[child].add(parent)
            tail = m[3][ref.end():refs[i+1].start() if i+1 < len(refs) else len(m[3])]
            action = re.match(r'\s*(?:MATCH\s+\w+\s*)?ON DELETE\s+(CASCADE|SET NULL|SET DEFAULT)', tail, re.I)
            if action:
                cascades[parent].add((child, 'DELETE' if action[1].upper() == 'CASCADE' else 'UPDATE'))

    # Static BEFORE/AFTER/CONSTRAINT triggers, including EXECUTE PROCEDURE.
    triggers = defaultdict(set)
    def add_trigger(table, name, timing, events, target, constraint=False):
        target = function(target)
        if target not in functions:
            raise ValueError('Unknown trigger function: ' + target)
        for event in re.findall(r'\b(?:' + EVENTS + r')\b', events.upper()):
            triggers[relation(table), event].add((target, name, timing.upper(), constraint))

    for m in re.finditer(r'CREATE(?: OR REPLACE)?\s+(CONSTRAINT\s+)?TRIGGER\s+(\w+)\s+'
                         r'(BEFORE|AFTER|INSTEAD OF)\s+([^;]*?)\bON\s+(' + IDENT + r')\b'
                         r'[^;]*?EXECUTE\s+(?:FUNCTION|PROCEDURE)\s+(' + IDENT + r')\s*\(', code, re.I):
        add_trigger(m[5], m[2], m[3], m[4], m[6], bool(m[1]))

    # Schema's generated append-only triggers: expand each literal FOREACH array
    # against its own loop body, not every table in the DO block.
    for loop in re.finditer(r'FOREACH\s+v_table\s+IN ARRAY ARRAY\[([^]]*)\]\s+LOOP(.*?)END LOOP;', ddl, re.I | re.S):
        names = re.findall(r"'([\w]+)'", loop[1])
        for m in re.finditer(r'CREATE TRIGGER %I (BEFORE|AFTER) (.*?) ON private\.%I.*?EXECUTE FUNCTION (' + IDENT + r')\(\)', loop[2], re.I | re.S):
            for table in names:
                add_trigger('private.' + table, 'trg_' + table + '_generated', m[1], m[2], m[3])

    # Generated log_change triggers, from the actual version registry rows.
    registry = set()
    for m in re.finditer(r'INSERT INTO version_pk_registry\b(.*?);', ddl, re.I | re.S):
        registry.update(re.findall(r"\(\s*'([\w]+)'\s*,\s*ARRAY", m[1]))
    if 'FOR r IN SELECT tabel FROM version_pk_registry LOOP' in ddl:
        for table in registry:
            add_trigger(table, 'trg_log_' + table, 'AFTER', 'INSERT UPDATE DELETE', 'log_change')

    calls, writes, locks = {}, {}, {}
    for name, (_, body) in functions.items():
        clean = scrub(body, strings=True)
        calls[name] = {function(m[1]) for m in re.finditer(r'(?<![\w.])(' + IDENT + r')\s*\(', clean)
                       if function(m[1]) in functions} - {name}
        writes[name] = set()
        for m in re.finditer(r'\b(INSERT\s+INTO|DELETE\s+FROM|UPDATE|TRUNCATE(?:\s+TABLE)?)\s+(?:ONLY\s+)?(' + IDENT + r')\b', clean, re.I):
            table = relation(m[2])
            if table in tables:
                writes[name].add((table, m[1].split()[0].upper()))
                # INSERT ... ON CONFLICT DO UPDATE may fire UPDATE triggers too.
                if m[1].upper().startswith('INSERT') and re.search(r'ON CONFLICT\b[^;]*\bDO UPDATE\b', clean[m.end():].split(';')[0], re.I):
                    writes[name].add((table, 'UPDATE'))
        locks[name] = {table for table, _ in writes[name] if table in FOCUS}
        for statement in clean.split(';'):
            if re.search(r'\b(?:LOCK\s+TABLE|FOR\s+(?:KEY\s+SHARE|SHARE|UPDATE|NO\s+KEY\s+UPDATE))\b', statement, re.I):
                locks[name].update(table for table in FOCUS if re.search(r'(?<![\w.])(?:' + re.escape(table) + '|' + re.escape(table.split('.')[1]) + r')\b', statement, re.I))

    # These helpers use format(%I) instead of a literal relation name.
    for name, event in [('_version_upsert_row', 'INSERT'), ('_version_upsert_row', 'UPDATE'),
                        ('_version_delete_row', 'DELETE')]:
        if name in functions:
            writes[name].update((relation(table), event) for table in registry)

    trigger_edges, fk_edges = {}, {}
    graph = {}
    for name in functions:
        trigger_edges[name], fk_edges[name] = set(), set()
        pending = list(writes[name])
        seen = set()
        while pending:
            table, event = pending.pop()
            if (table, event) in seen:
                continue
            seen.add((table, event))
            for target, trigger, timing, constraint in triggers[table, event]:
                trigger_edges[name].add((table, event, trigger, timing, constraint, target))
            if event in ('INSERT', 'UPDATE'):
                fk_edges[name].update((table, parent) for parent in fks[table])
            if event == 'DELETE':
                pending.extend(cascades[table])
        graph[name] = calls[name] | {edge[-1] for edge in trigger_edges[name]}
        locks[name].update(parent for _, parent in fk_edges[name] if parent in FOCUS)

    selected = {name for name in functions if locks[name]} | (EXTRA & functions.keys())
    while True:
        # Reverse closure discovers writers through triggers and helper calls.
        # Forward trigger closure also keeps nonlocking constraint validators.
        new = selected | {name for name in functions if graph[name] & selected}
        new |= {edge[-1] for name in selected for edge in trigger_edges[name]}
        if new == selected:
            break
        selected = new
    return functions, selected, locks, calls, trigger_edges, fk_edges


def render(sql):
    functions, selected, locks, calls, trigger_edges, fk_edges = inventory(sql)
    rows = []
    for name in sorted(selected):
        trigger_text = ','.join(f'{table}:{event}->{timing}{" CONSTRAINT" if constraint else ""}:{trigger}->{target}'
                                for table, event, trigger, timing, constraint, target in sorted(trigger_edges[name]))
        fk_text = ','.join(f'{child}->{parent}:KEY SHARE' for child, parent in sorted(fk_edges[name]))
        rows.append('\t'.join(value or '-' for value in
                              (name, f'schema.sql:{functions[name][0]}', ','.join(sorted(locks[name])),
                               ','.join(sorted(calls[name] & selected)), trigger_text, fk_text)))
    return '\n'.join(rows) + '\n'


if __name__ == '__main__':
    print(render(pathlib.Path('schema.sql').read_text()), end='')

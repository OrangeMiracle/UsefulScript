"""Offline, manual ChatGPT catalog maintenance. Never makes network requests."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import traceback

ROOT = Path(__file__).resolve().parent
RUNS = ROOT / 'runs'
DBROOT = Path.home() / '.codex' / 'sqlite'
TTL = 7200


def now():
    return dt.datetime.now(dt.timezone.utc)


def save(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), 'utf-8')


def read(path):
    return json.loads(Path(path).read_text('utf-8-sig'))


def event(run, name, **data):
    with (run / 'run.jsonl').open('a', encoding='utf-8') as f:
        f.write(json.dumps(dict(time=now().isoformat(), event=name, **data), ensure_ascii=False) + '\n')


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def connect(path, ro=True):
    c = sqlite3.connect(Path(path).resolve().as_uri() + ('?mode=ro' if ro else '?mode=rw'), uri=True, timeout=5)
    c.row_factory = sqlite3.Row
    c.execute('PRAGMA query_only=ON' if ro else 'PRAGMA foreign_keys=ON')
    if not ro:
        c.execute('PRAGMA synchronous=FULL')
    return c


def schema(c):
    return [list(r) for r in c.execute('SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name')]


def check(c):
    checks = [r[0] for r in c.execute('PRAGMA integrity_check')]
    foreign = [list(r) for r in c.execute('PRAGMA foreign_key_check')]
    if checks != ['ok'] or foreign:
        raise RuntimeError('Database integrity check failed')
    return dict(integrity_check=checks, foreign_key_check=foreign)


def protected(c, keys):
    result = {}
    for kind, table, _, _ in schema(c):
        if kind != 'table':
            continue
        rows = []
        for r in c.execute('SELECT * FROM ' + quote(table)):
            row = dict(r)
            if table == 'local_thread_catalog' and (row['host_id'], row['thread_id']) in keys:
                continue
            if table == 'local_thread_catalog_metadata' and row['id'] == 1:
                row['catalog_revision'] = 0
            rows.append(json.dumps(row, sort_keys=True, ensure_ascii=False, default=lambda b: {'bytes': b.hex()}))
        result[table] = hashlib.sha256('\n'.join(sorted(rows)).encode()).hexdigest()
    return result


def age(stamp):
    return (now() - dt.datetime.fromisoformat(stamp.replace('Z', '+00:00'))).total_seconds()


def parse_log(path, pids, process_started=None):
    """Require current process + one unambiguous account in this physical log."""
    match = re.search(r'-(\d+)-t\d+-i\d+-', path.name)
    if not match or int(match[1]) not in pids:
        return [], False
    lines = path.read_text('utf-8', errors='replace').splitlines()
    identities = set()
    for line in lines:
        if 'notificationId=' not in line or '[desktop-notifications]' not in line:
            continue
        for account, user in re.findall(r'\["([0-9a-f-]{36})","(user-[A-Za-z0-9]+)"', line):
            identities.add('chatgpt:' + account + ':' + user)
    result = []
    limited = False
    for number, line in enumerate(lines, 1):
        try:
            stamp = line.split()[0]
            fresh = 0 <= age(stamp) <= TTL
            if process_started and stamp < process_started.get(str(int(match[1])), '9999'):
                fresh = False
        except (ValueError, IndexError):
            continue
        if not fresh or 'sa_server_request_failed ' not in line:
            continue
        if 'status=429 ' in line:
            limited = True
        if len(identities) != 1:
            continue
        if not all(x in line for x in ['attachAuth=true ', 'errorCode=conversation_deleted ', 'status=404 ', 'method=get ']):
            continue
        url = re.search(r'\burl=/conversations/([0-9a-f-]{36})(?:\?|\s|$)', line)
        body = re.search(r'\berrorMessage=(\{.*?\})\s+errorName=', line)
        if not url or not body:
            continue
        try:
            detail = json.loads(body[1])['detail']
        except (ValueError, KeyError, TypeError):
            continue
        if detail.get('code') != 'conversation_deleted' or detail.get('conversation_id') != url[1]:
            continue
        result.append(dict(host_id=next(iter(identities)), thread_id=url[1], timestamp=line.split()[0],
                           file=str(path), line=number, log_text=line,
                           sha256=hashlib.sha256(line.encode()).hexdigest()))
    return result, limited


def allowed_path(path):
    path = Path(path).resolve()
    if path not in [(DBROOT / n).resolve() for n in ('codex.db', 'codex-dev.db')]:
        raise RuntimeError('Unexpected database path')
    return path


def validate_schema(c):
    actual = schema(c)
    supported = read(ROOT / 'supported-schemas.json')
    if actual not in supported.values():
        raise RuntimeError('Client schema changed; audit only, manual adapter review required')
    pk = [r['name'] for r in c.execute('PRAGMA table_xinfo(local_thread_catalog)') if r['pk']]
    if pk != ['host_id', 'thread_id']:
        raise RuntimeError('Unexpected catalog key')
    return actual


def prepare(run):
    from windows_handles import owners
    context = read(run / 'context.json')
    pids = set(context['pids'])
    evidence = []
    limited = False
    # Explicit physical MSIX location; never depend on AppData virtualization.
    logroots = [Path(context['local_appdata']) / 'Packages' / context['package_family'] / 'LocalCache/Local/Codex/Logs']
    for logroot in logroots:
        if logroot.is_dir():
            for path in logroot.rglob('*.log'):
                if now().timestamp() - path.stat().st_mtime > TTL:
                    continue
                found, hit = parse_log(path, pids, context['process_started'])
                evidence.extend(found)
                limited |= hit
    reports = []
    plans = []
    for name in ('codex.db', 'codex-dev.db'):
        path = DBROOT / name
        if not path.is_file():
            continue
        listing = owners(path)
        active = any(r['pid'] in pids for r in listing)
        c = connect(path)
        try:
            structure = schema(c)
            tables = {r[1] for r in structure if r[0] == 'table'}
            if 'local_thread_catalog' not in tables:
                reports.append(dict(database=str(path), active=active, error='No catalog table'))
                continue
            columns = {r['name'] for r in c.execute('PRAGMA table_xinfo(local_thread_catalog)')}
            if not {'host_id', 'thread_id', 'source_kind', 'cwd', 'missing_candidate'} <= columns:
                reports.append(dict(database=str(path), active=active, error='Unknown catalog columns'))
                continue
            rows = [dict(r) for r in c.execute('SELECT * FROM local_thread_catalog')]
            hosts = {r['host_id'] for r in c.execute("SELECT * FROM local_thread_catalog_hosts WHERE host_kind='chatgpt'")}
            hits = []
            targets = []
            for r in rows:
                if r['source_kind'] != 'chatgpt' or r['host_id'] not in hosts or r['cwd'] is not None:
                    continue
                ev = [e for e in evidence if (e['host_id'], e['thread_id']) == (r['host_id'], r['thread_id'])]
                if ev:
                    targets.append(r)
                    hits.append(max(ev, key=lambda e: e['timestamp']))
            supported = structure in read(ROOT / 'supported-schemas.json').values()
            reports.append(dict(database=str(path), active=active, owners=listing, schema_supported=supported,
                                catalog_count=len(rows), explicit_candidates=len(targets),
                                missing_candidates=sum(bool(r['missing_candidate']) for r in rows if r['source_kind']=='chatgpt'),
                                candidates=[dict(thread_id=r['thread_id'], title=r['display_title']) for r in targets], integrity=check(c)))
            # Multiple account catalogs are intentionally review-only.
            if active and supported and targets and len(hosts) == 1 and not limited:
                validate_schema(c)
                plans.append(dict(database=str(path.resolve()), schema=structure, rows=targets, evidence=hits,
                                  created_at=now().isoformat(), app_path=context['app_path'], package_family=context['package_family']))
        finally:
            c.close()
    if len(plans) > 1:
        raise RuntimeError('Multiple active catalog databases; refusing ambiguous repair')
    save(run / 'audit.json', dict(time=now().isoformat(), databases=reports, rate_limit_seen=limited,
                                 network_requests=0, database_modified=False))
    if plans:
        save(run / 'plan.json', plans[0])
    event(run, 'prepared', plans=len(plans), network_requests=0, rate_limit_seen=limited)
    print('Verified candidates: ' + str(len(plans[0]['rows']) if plans else 0))


def validate_evidence(plan):
    if not 0 <= age(plan['created_at']) <= TTL:
        raise RuntimeError('Plan expired')
    for e in plan['evidence']:
        if not 0 <= age(e['timestamp']) <= TTL:
            raise RuntimeError('Deletion evidence expired')
        line = Path(e['file']).read_text('utf-8', errors='replace').splitlines()[e['line']-1]
        if line != e['log_text'] or hashlib.sha256(line.encode()).hexdigest() != e['sha256']:
            raise RuntimeError('Physical deletion evidence changed')


def commit_plan(path, plan, run, rollback=False):
    """Caller checks process/handle quiescence. Transaction is all-or-nothing."""
    keys = {(r['host_id'], r['thread_id']) for r in plan['rows']}
    if not keys or len(keys) != len(plan['rows']):
        raise RuntimeError('Empty or duplicate targets')
    c = connect(path, False)
    try:
        if schema(c) != plan['schema']:
            raise RuntimeError('Schema changed after planning')
        hosts = {r['host_id'] for r in c.execute("SELECT * FROM local_thread_catalog_hosts WHERE host_kind='chatgpt'")}
        if any(r['source_kind'] != 'chatgpt' or r['host_id'] not in hosts or r['cwd'] is not None for r in plan['rows']):
            raise RuntimeError('Protected record in plan')
        check(c)
        backup = run / 'before.db'
        if backup.exists():
            raise RuntimeError('Backup exists; refusing repeat execution')
        b = sqlite3.connect(str(backup))
        try:
            c.backup(b)
        finally:
            b.close()
        b = connect(backup)
        try:
            check(b)
            expected = protected(b, keys)
            revision = b.execute('SELECT catalog_revision FROM local_thread_catalog_metadata WHERE id=1').fetchone()[0]
        finally:
            b.close()
        event(run, 'consistent_backup', path=str(backup), sha256=hashlib.sha256(backup.read_bytes()).hexdigest())
        c.execute('BEGIN IMMEDIATE')
        if protected(c, keys) != expected or c.execute('SELECT catalog_revision FROM local_thread_catalog_metadata WHERE id=1').fetchone()[0] != revision:
            raise RuntimeError('Database changed after backup')
        for r in plan['rows']:
            row = c.execute('SELECT * FROM local_thread_catalog WHERE host_id=? AND thread_id=?', (r['host_id'], r['thread_id'])).fetchone()
            if rollback:
                if row is not None:
                    raise RuntimeError('Rollback target already exists')
                cols = list(r)
                c.execute('INSERT INTO local_thread_catalog (' + ','.join(map(quote, cols)) + ') VALUES (' + ','.join('?' for _ in cols) + ')', [r[k] for k in cols])
            else:
                if row is None or dict(row) != r:
                    raise RuntimeError('Target changed; entire transaction cancelled')
                if c.execute('DELETE FROM local_thread_catalog WHERE host_id=? AND thread_id=? AND source_kind=?', (r['host_id'],r['thread_id'],'chatgpt')).rowcount != 1:
                    raise RuntimeError('Unexpected deletion count')
        if c.execute('UPDATE local_thread_catalog_metadata SET catalog_revision=catalog_revision+1 WHERE id=1 AND catalog_revision=?', (revision,)).rowcount != 1:
            raise RuntimeError('Revision changed')
        if protected(c, keys) != expected:
            raise RuntimeError('Protected data changed')
        check(c)
        c.commit()
        # Record the commit before any subsequent verification/checkpoint can fail.
        result = dict(status='rollback_committed' if rollback else 'repair_committed', time=now().isoformat(),
                      database=str(path), changed_records=len(keys), revision_before=revision, revision_after=revision+1,
                      backup=str(backup), protected_data_unchanged=True)
        save(run / 'result.json', result)
        event(run, result['status'], count=len(keys))
        result['integrity'] = check(c)
        save(run / 'result.json', result)
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        return result
    except BaseException:
        if c.in_transaction:
            c.rollback()
        raise
    finally:
        c.close()


def apply(run, rollback=False):
    from windows_handles import require_quiet
    plan = read(run / 'plan.json')
    path = allowed_path(plan['database'])
    if not rollback:
        validate_evidence(plan)
    else:
        original = read(Path(plan['original_run']) / 'result.json')
        if original['status'] != 'repair_committed':
            raise RuntimeError('No successful repair to roll back')
    require_quiet(path, run)
    c = connect(path)
    try:
        validate_schema(c)
    finally:
        c.close()
    print(json.dumps(commit_plan(path, plan, run, rollback), ensure_ascii=False))


def verify(run, rollback=False):
    plan = read(run / 'plan.json')
    c = connect(allowed_path(plan['database']))
    try:
        check(c)
        for r in plan['rows']:
            row = c.execute('SELECT * FROM local_thread_catalog WHERE host_id=? AND thread_id=?', (r['host_id'], r['thread_id'])).fetchone()
            if (row is None) == rollback:
                raise RuntimeError('Post-restart target verification failed')
        save(run / 'post-restart.json', dict(status='verified', rollback=rollback, time=now().isoformat(), checked=len(plan['rows'])))
    finally:
        c.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['prepare','apply','verify','rollback','verify-rollback','prepare-rollback'])
    p.add_argument('--run', required=True)
    args = p.parse_args()
    run = Path(args.run).resolve()
    if not run.is_relative_to(RUNS.resolve()) or run == RUNS.resolve():
        raise RuntimeError('Run directory must be inside the cleaner runs folder')
    run.mkdir(parents=True, exist_ok=True)
    try:
        if args.mode == 'prepare':
            prepare(run)
        elif args.mode == 'prepare-rollback':
            candidates = sorted([r for r in RUNS.iterdir() if r.is_dir() and r != run and (r/'result.json').is_file()
                                 and read(r/'result.json').get('status') == 'repair_committed'], reverse=True)
            if not candidates:
                raise RuntimeError('No successful repair found')
            original = candidates[0]
            plan = read(original/'plan.json')
            plan['original_run'] = str(original)
            save(run/'plan.json',plan)
        elif args.mode in ['verify','verify-rollback']:
            verify(run, args.mode == 'verify-rollback')
        else:
            apply(run, args.mode == 'rollback')
    except BaseException:
        event(run, 'failed', traceback=traceback.format_exc())
        raise


if __name__ == '__main__':
    main()

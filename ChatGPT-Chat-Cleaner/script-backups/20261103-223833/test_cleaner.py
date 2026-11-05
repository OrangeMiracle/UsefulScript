"""Destructive-path tests use temporary SQLite fixtures, never the user's DB."""
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

import cleaner as m


class CleanerTests(unittest.TestCase):
    def setUp(self):
        self.testroot = m.ROOT / 'test-work'
        self.testroot.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=self.testroot)
        self.root = Path(self.temp.name)
        self.db = self.root/'fixture.db'
        self.host = 'chatgpt:11111111-1111-1111-1111-111111111111:user-fixture'
        c = sqlite3.connect(self.db)
        structure = m.read(m.ROOT/'supported-schemas.json')['codex.db']
        for kind in ['table','index','trigger','view']:
            for typ, name, _, sql in structure:
                if typ == kind and sql and not name.startswith('sqlite_'):
                    c.execute(sql)
        c.execute('INSERT INTO local_thread_catalog_hosts(host_id,host_kind) VALUES (?,?)',(self.host,'chatgpt'))
        c.execute('INSERT INTO local_thread_catalog_hosts(host_id,host_kind) VALUES (?,?)',('local','local'))
        c.execute('INSERT INTO local_thread_catalog_metadata(id,catalog_revision) VALUES (1,7)')
        for host,tid,source in [(self.host,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','chatgpt'),(self.host,'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','chatgpt'),('local','local-task','vscode')]:
            c.execute('INSERT INTO local_thread_catalog(host_id,thread_id,display_title,source_created_at,source_updated_at,source_kind,observation_sequence) VALUES (?,?,?,?,?,?,?)',(host,tid,tid,1,2,source,1))
        c.commit();c.close()
        c = m.connect(self.db)
        row = dict(c.execute('SELECT * FROM local_thread_catalog WHERE thread_id=?',('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',)).fetchone())
        self.plan = dict(schema=m.schema(c), rows=[row])
        self.before = m.protected(c,{(row['host_id'],row['thread_id'])})
        c.close()

    def tearDown(self):
        assert self.root.resolve().is_relative_to(self.testroot.resolve())
        self.temp.cleanup()

    def folder(self, name):
        p=self.root/name;p.mkdir();return p

    def test_delete_and_selective_rollback_preserve_other_data(self):
        result=m.commit_plan(self.db,self.plan,self.folder('delete'))
        self.assertEqual(result['changed_records'],1)
        c=m.connect(self.db)
        self.assertEqual(c.execute('SELECT count(*) FROM local_thread_catalog').fetchone()[0],2)
        self.assertEqual(c.execute('SELECT catalog_revision FROM local_thread_catalog_metadata').fetchone()[0],8)
        self.assertEqual(m.protected(c,{(self.host,self.plan['rows'][0]['thread_id'])}),self.before);c.close()
        m.commit_plan(self.db,self.plan,self.folder('undo'),True)
        c=m.connect(self.db)
        self.assertEqual(c.execute('SELECT count(*) FROM local_thread_catalog').fetchone()[0],3)
        self.assertEqual(c.execute('SELECT catalog_revision FROM local_thread_catalog_metadata').fetchone()[0],9)
        self.assertEqual(m.protected(c,{(self.host,self.plan['rows'][0]['thread_id'])}),self.before);c.close()

    def test_changed_row_rolls_back_transaction(self):
        c=sqlite3.connect(self.db);c.execute("UPDATE local_thread_catalog SET display_title='changed' WHERE thread_id=?",(self.plan['rows'][0]['thread_id'],));c.commit();c.close()
        with self.assertRaisesRegex(RuntimeError,'Target changed'):
            m.commit_plan(self.db,self.plan,self.folder('changed'))
        c=m.connect(self.db)
        self.assertEqual(c.execute('SELECT count(*) FROM local_thread_catalog').fetchone()[0],3)
        self.assertEqual(c.execute('SELECT catalog_revision FROM local_thread_catalog_metadata').fetchone()[0],7);c.close()

    def test_schema_change_rejected(self):
        c=sqlite3.connect(self.db);c.execute('CREATE TABLE unexpected(value TEXT)');c.close()
        with self.assertRaisesRegex(RuntimeError,'Schema changed'):
            m.commit_plan(self.db,self.plan,self.folder('schema'))

    def test_local_task_rejected(self):
        c=m.connect(self.db);bad=dict(self.plan,rows=[dict(c.execute("SELECT * FROM local_thread_catalog WHERE source_kind='vscode'").fetchone())]);c.close()
        with self.assertRaisesRegex(RuntimeError,'Protected record'):
            m.commit_plan(self.db,bad,self.folder('local'))

    def log(self, identity=True, status='404', code='conversation_deleted', extra=''):
        stamp=m.now().isoformat().replace('+00:00','Z')
        tid=self.plan['rows'][0]['thread_id']
        lines=[]
        if identity:
            lines.append(stamp+' info [desktop-notifications] notificationId=turn-["11111111-1111-1111-1111-111111111111","user-fixture","local"]')
        detail=json.dumps(dict(detail=dict(code=code,conversation_id=tid)),separators=(',',':'))
        lines.append(stamp+' warning sa_server_request_failed attachAuth=true errorCode='+code+' errorMessage='+detail+' errorName=Error method=get status='+status+' url=/conversations/'+tid+'?num_turns=10')
        p=self.root/'codex-desktop-fixture-123-t0-i1-000000-0.log'
        p.write_text('\n'.join(lines)+extra,'utf-8');return p

    def test_evidence_requires_current_process_and_account(self):
        self.assertEqual(len(m.parse_log(self.log(),{123})[0]),1)
        self.assertEqual(m.parse_log(self.log(),{456})[0],[])
        self.assertEqual(m.parse_log(self.log(False),{123})[0],[])
        extra='\n'+m.now().isoformat().replace('+00:00','Z')+' info [desktop-notifications] notificationId=turn-["22222222-2222-2222-2222-222222222222","user-other","local"]'
        self.assertEqual(m.parse_log(self.log(extra=extra),{123})[0],[])

    def test_429_and_generic_404_never_authorize_deletion(self):
        hits,limited=m.parse_log(self.log(status='429',code='rate_limited'),{123})
        self.assertFalse(hits);self.assertTrue(limited)
        self.assertFalse(m.parse_log(self.log(code='conversation_not_found'),{123})[0])


if __name__=='__main__':
    unittest.main()

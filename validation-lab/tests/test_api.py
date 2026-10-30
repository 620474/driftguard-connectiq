import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from driftlab.garmin import Client,TOKEN,sync,fits_from_download,secret
from test_lab import fixture


class ApiTests(unittest.TestCase):
    def test_exchange_bearer(self):
        requests=[]
        def transport(req,timeout):
            requests.append(req)
            return io.BytesIO(b'"access"' if req.full_url.endswith(TOKEN) else b'[]')
        c=Client('synthetic-key',transport,sleep=lambda _:None)
        self.assertEqual(c.request('/activitylist-service/activities/search/activities'),b'[]')
        self.assertEqual(requests[0].get_header('Authorization'),'ApiKey synthetic-key')
        self.assertEqual(requests[1].get_header('Authorization'),'Bearer access')
    def test_429_retry(self):
        calls=[]
        def transport(req,timeout):
            calls.append(req)
            if len(calls)==1:raise HTTPError(req.full_url,429,'limited',{'Retry-After':'1'},None)
            return io.BytesIO(b'access')
        waits=[];c=Client('synthetic',transport,sleep=waits.append);c.authorize()
        self.assertEqual(waits,[1]);self.assertEqual(c.token,'access')
    def test_401_reauthorize(self):
        calls=[]
        def transport(req,timeout):
            calls.append(req.full_url)
            if len(calls)==2:raise HTTPError(req.full_url,401,'expired',{},None)
            return io.BytesIO(b'access' if req.full_url.endswith(TOKEN) else b'[]')
        c=Client('synthetic',transport,sleep=lambda _:None)
        self.assertEqual(c.request('/search'),b'[]');self.assertEqual(len(calls),4)
    def test_no_error_body_disclosure(self):
        def transport(req,timeout):raise HTTPError(req.full_url,403,'SECRET',{},None)
        with self.assertRaisesRegex(RuntimeError,'HTTP 403') as ctx:Client('SECRET',transport).authorize()
        self.assertNotIn('SECRET',str(ctx.exception))
    def test_zip_and_incremental(self):
        raw=io.BytesIO()
        with zipfile.ZipFile(raw,'w') as z:z.writestr('../original.fit',fixture())
        self.assertEqual(fits_from_download(raw.getvalue()),[fixture()])
        class Fake:
            def __init__(self):self.downloads=0
            def sleep(self,_):pass
            def request(self,path):
                if 'search' in path:return json.dumps([dict(activityId=123)]).encode()
                self.downloads+=1;return raw.getvalue()
        with tempfile.TemporaryDirectory() as d:
            c=Fake();self.assertEqual(sync(d,c),1);self.assertEqual(sync(d,c),0)
            self.assertEqual(c.downloads,1);self.assertTrue((Path(d)/'archive/garmin-123-0.fit').exists())
    def test_empty_key(self):
        with tempfile.TemporaryDirectory() as d,patch.dict('os.environ',{'GARMIN_PERSONAL_API_KEY':''}):
            with patch('pathlib.Path.exists',return_value=False):
                with self.assertRaises(RuntimeError):secret(d)

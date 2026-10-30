import io,json,tempfile,sys,unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from research import intervals


class ResearchApiTests(unittest.TestCase):
    def test_intervals_read_only_auth_contract(self):
        requests=[]
        class Opener:
            def open(self,request,timeout):
                requests.append(request)
                return io.BytesIO(b'[{"id":"i1","external_id":"123","decoupling":2.5}]')
        with tempfile.TemporaryDirectory() as d,patch('research.env_values',return_value={'INTERVALS_API_KEY':'synthetic','INTERVALS_ATHLETE_ID':'0'}),patch('research.build_opener',return_value=Opener()):
            result=intervals(Path(d),'2026-04-30','2026-10-30')
            self.assertEqual(result['status'],'downloaded')
            self.assertEqual(requests[0].get_method(),'GET')
            self.assertEqual(requests[0].get_header('Authorization'),'Basic QVBJX0tFWTpzeW50aGV0aWM=')
            self.assertNotIn('synthetic',requests[0].full_url)
            self.assertIn('oldest=2026-04-30',requests[0].full_url)
    def test_intervals_failure_has_no_secrets(self):
        class Opener:
            def open(self,request,timeout):raise HTTPError(request.full_url,403,'synthetic-secret',{},None)
        with tempfile.TemporaryDirectory() as d,patch('research.env_values',return_value={'INTERVALS_API_KEY':'synthetic-secret'}),patch('research.build_opener',return_value=Opener()):
            result=intervals(Path(d),'2026-04-30','2026-10-30')
            self.assertEqual(result,{'status':'http_403','activities':[]})
            self.assertNotIn('synthetic-secret',json.dumps(result))

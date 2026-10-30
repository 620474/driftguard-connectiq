"""Official Garmin Personal API, verified against Garmin Swagger 2026-10-30."""
import io
import json
import os
import subprocess
import time
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.request import Request,urlopen,HTTPRedirectHandler,build_opener
from urllib.error import HTTPError,URLError
from urllib.parse import urlencode
from dateutil.relativedelta import relativedelta
from .archive import atomic,digest

BASE='https://personal.connectapi.garmin.com'
TOKEN='/personalapitoken-service/personal-api/personal-api-key/token'


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise RuntimeError('Unexpected API redirect; refused to forward credentials')


def secret(root):
    value=os.environ.get('GARMIN_PERSONAL_API_KEY')
    env_file=Path(__file__).resolve().parents[1]/'.env'
    if not value and env_file.exists():
        for line in env_file.read_text('utf-8-sig').splitlines():
            name,sep,entry=line.strip().partition('=')
            if sep and name.strip()=='GARMIN_PERSONAL_API_KEY':
                value=entry.strip()
                if len(value)>=2 and value[0]==value[-1] and value[0] in ('"', "'"):
                    value=value[1:-1]
    if value: return value
    path=Path(root)/'garmin-key.xml'
    if not path.exists(): raise RuntimeError('Run lab.ps1 auth first, or set GARMIN_PERSONAL_API_KEY locally. Do not paste it into chat.')
    if os.name!='nt': raise RuntimeError('DPAPI key requires Windows; use environment variable')
    env=os.environ.copy();env['DRIFTLAB_KEY_PATH']=str(path.resolve())
    p=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',
        '$s=Import-Clixml -LiteralPath $env:DRIFTLAB_KEY_PATH; $c=New-Object System.Net.NetworkCredential("",$s); [Console]::Write($c.Password)'],
        env=env,capture_output=True,text=True)
    if p.returncode or not p.stdout: raise RuntimeError('Cannot decrypt Garmin key under current Windows user')
    return p.stdout.strip()


class Client:
    def __init__(self,key,transport=None,sleep=time.sleep):
        self.key=key;self.token=None;self.sleep=sleep
        self.transport=transport or build_opener(NoRedirect()).open

    def request(self,path,method='GET',auth_retry=True):
        if path!=TOKEN and self.token is None: self.authorize()
        auth='ApiKey '+self.key if path==TOKEN else 'Bearer '+self.token
        for attempt in range(5):
            req=Request(BASE+path,method=method,headers={'Authorization':auth,'Accept':'*/*'})
            try:
                with self.transport(req,timeout=60) as response:
                    content=response.read(100*1024*1024+1)
                    if len(content)>100*1024*1024: raise RuntimeError('API response exceeds 100 MiB')
                    return content
            except HTTPError as e:
                if e.code==401 and path!=TOKEN and auth_retry:
                    self.authorize();return self.request(path,method,False)
                if e.code not in (429,500,502,503,504):
                    raise RuntimeError(f'Garmin HTTP {e.code}; check key expiry/permissions; credentials were not logged') from None
                if attempt==4: raise RuntimeError(f'Garmin HTTP {e.code}; retry budget exhausted') from None
                retry=e.headers.get('Retry-After','') if e.headers else ''
                delay=float(retry) if retry.isdigit() else 2**attempt
                if delay>60: raise RuntimeError('Garmin requests a long rate-limit wait; rerun later') from None
                self.sleep(delay)
            except (URLError,TimeoutError):
                if attempt==4: raise RuntimeError('Garmin network retry budget exhausted') from None
                self.sleep(2**attempt)

    def authorize(self):
        raw=self.request(TOKEN,'POST').decode().strip()
        try:
            data=json.loads(raw)
            token=data if isinstance(data,str) else data.get('access_token',data.get('accessToken'))
        except json.JSONDecodeError:
            token=raw
        if not isinstance(token,str) or not token or any(c.isspace() for c in token):
            raise RuntimeError('Unrecognized token response; no response body logged')
        self.token=token


def fits_from_download(raw):
    if raw[:2]==b'PK':
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            members=[i for i in z.infolist() if i.filename.lower().endswith('.fit') and not i.is_dir()]
            if not members: raise ValueError('original archive contains no FIT')
            if sum(i.file_size for i in members)>100*1024*1024:raise ValueError('uncompressed FIT size exceeds 100 MiB')
            return [z.read(i) for i in members]
    if len(raw)>=12 and raw[8:12]==b'.FIT':return [raw]
    raise ValueError('original download is not FIT or ZIP containing FIT')


def sync(root,client=None,months=6):
    root=Path(root);archive=root/'archive';archive.mkdir(parents=True,exist_ok=True)
    manifest_path=root/'sync.json'
    manifest=json.loads(manifest_path.read_text('utf-8')) if manifest_path.exists() else {}
    client=client or Client(secret(root))
    now=datetime.now().astimezone();since=now-relativedelta(months=months)
    offset=downloaded=0;failures=[]
    while True:
        query=urlencode(dict(start=offset,limit=99,activityType='cycling',startDate=since.date().isoformat(),endDate=now.date().isoformat(),sortOrder='desc',excludeChildren='false'))
        page=json.loads(client.request('/activitylist-service/activities/search/activities?'+query))
        if not isinstance(page,list):raise RuntimeError('Unexpected activity search schema')
        if not page:break
        for activity in page:
            aid=str(activity.get('activityId',''))
            if not aid.isdigit():raise RuntimeError('Invalid activity ID returned')
            existing=manifest.get(aid,[])
            if existing and all((archive/v['file']).exists() and digest(archive/v['file'])==v['sha256'] for v in existing):continue
            try:
                files=fits_from_download(client.request('/download-service/files/activity/'+aid))
                entries=[]
                for i,raw in enumerate(files):
                    name=f'garmin-{aid}-{i}.fit'
                    # Never overwrite an existing original with changed bytes.
                    target=archive/name
                    if target.exists() and target.read_bytes()!=raw:
                        import hashlib
                        target=archive/f'garmin-{aid}-{i}-{hashlib.sha256(raw).hexdigest()[:16]}.fit'
                    atomic(target,raw);entries.append(dict(file=target.name,sha256=digest(target)))
                manifest[aid]=entries
                atomic(manifest_path,json.dumps(manifest).encode());downloaded+=1
                client.sleep(.3)
            except (ValueError,RuntimeError,zipfile.BadZipFile) as exc:
                failures.append(dict(activity_id=aid,error=str(exc)))
        offset+=len(page)
        if len(page)<99:break
    atomic(root/'sync-failures.json',json.dumps(failures).encode())
    if failures:raise RuntimeError(f'{len(failures)} downloads failed; completed files retained. Rerun sync to retry.')
    return downloaded

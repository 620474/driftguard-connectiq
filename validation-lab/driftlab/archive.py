"""Non-destructive content-addressed manual archive adapter."""
import hashlib
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic(path, data):
    path=Path(path)
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix(path.suffix+'.part')
    tmp.write_bytes(data)
    tmp.replace(path)


def sync_import(source, archive):
    archive=Path(archive); archive.mkdir(parents=True,exist_ok=True)
    count=0
    for p in Path(source).rglob('*'):
        if p.is_file() and p.suffix.lower()=='.fit':
            target=archive/(digest(p)+'.fit')
            if not target.exists():
                atomic(target,p.read_bytes()); count+=1
    return count

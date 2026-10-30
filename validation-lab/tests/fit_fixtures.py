"""Small complete binary FIT v2 fixtures, including UUID and scalar definitions."""
import struct
import tempfile
from pathlib import Path
from driftlab.calibration_schema import SCHEMA, CALIBRATION_APP_ID
from driftlab.calibration_config import ALGO_VERSION, CONFIG_CRC
from driftlab.fitio import read_fit
from test_lab import crc


def decode_fixture(apps=(CALIBRATION_APP_ID,), omit=(), override=None, null=(), delta=None,
                   sequence_gap=False, conflict=False, duplicate=False):
    override=override or {}
    entries=[]
    for name,(kind,number,base,size) in SCHEMA.items():
        if name not in omit:
            kind,number,base,size=override.get(name,(kind,number,base,size))
            entries.append((name,kind,number,base,size))
    body=b''
    for index,app in enumerate(apps):
        body+=bytes([0x40,0,0,207,0,2,3,1,2,1,16,0x0d])
        body+=bytes([0,index])+bytes.fromhex(app)
        for name,kind,number,base,size in entries:
            encoded=name.encode()+b'\0'
            body+=bytes([0x41,0,0,206,0,4,0,1,2,1,1,2,2,1,2,3,len(encoded),7])
            body+=bytes([1,index,number,base])+encoded
    values=dict(dg_ef=2.,dg_steady=0,dg_ride_drift=None,dg_ride_state=0,dg_cadence=90,
        dg_ride_drift_final=None,dg_ride_state_final=0,dg_steady_percent=0,dg_power_change=None,
        dg_compat_drift=0.,dg_algo_version=ALGO_VERSION,dg_config_crc=CONFIG_CRC,
        dg_bucket_width=1,dg_compat_width=1)

    def definition(kind,local,global_num,native):
        dev=[(index,e) for index in range(len(apps)) for e in entries if e[1]==kind]
        if duplicate and kind=='record':
            dev.append(dev[0])
        payload=bytes([0x60|local,0,0,global_num,0,len(native)])
        for num,size,base in native:payload+=bytes([num,size,base])
        payload+=bytes([len(dev)])
        for index,(_,_,num,_,size) in dev:payload+=bytes([num,size,index])
        return payload,dev

    def pack(dev):
        data=b''
        for index,(name,kind,num,base,size) in dev:
            value=values.get(name)
            if name in null:value=None
            if value is None:
                data+=struct.pack('<f',float('nan')) if base==0x88 else bytes([255])*size
            elif base==0x88:data+=struct.pack('<f',value)
            else:data+=int(value).to_bytes(size,'little')
        return data

    definition_bytes,dev=definition('record',2,20,[(253,4,0x86),(7,2,0x84),(3,1,2)])
    body+=definition_bytes
    for second in range(120):
        n=(second+1)//60
        if sequence_gap and n==1:n=2
        values.update(dg_ride_state=0,dg_minute_seq=n,dg_sample_seq=n*60,dg_valid_seconds=60 if n else 0,
            dg_reject_reason=0,dg_min_power_sum=12000 if n else 0,dg_min_hr_sum=6000 if n else 0,
            dg_compat_seconds=60 if n else 0,dg_compat_power_sum=12000 if n else 0,
            dg_compat_hr_sum=6000 if n else 0)
        if n and delta:
            for key,amount in delta.items():values[key]+=amount
        if conflict and second==60:values['dg_valid_seconds']=48
        body+=bytes([2])+struct.pack('<IHB',1162224000+second,200,100)+pack(dev)
    definition_bytes,dev=definition('session',3,18,[(5,1,0)])
    body+=definition_bytes+bytes([3,2])+pack(dev)
    data=struct.pack('<BBHI4s',12,0x20,2100,len(body),b'.FIT')+body
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'calibration.fit'
        path.write_bytes(data+struct.pack('<H',crc(data)))
        return read_fit(path)

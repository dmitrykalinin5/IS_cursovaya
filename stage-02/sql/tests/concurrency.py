#!/usr/bin/env python3
"""Real two-connection tests. Standard library + psql; isolated DB only."""
import os, subprocess, time, json
from pathlib import Path
PSQL=['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']

def sql(query):
    p=subprocess.run(PSQL+['-c',query],capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    return p.stdout.strip()

assert sql('SELECT current_database()')=='labreserve_stage02_test'
results=[]

def race(label,first,second,expected,check,isolation='READ COMMITTED'):
    # Signal that connection A holds the equipment lock through pg_stat_activity.
    a=subprocess.Popen(PSQL+['-c',f"BEGIN ISOLATION LEVEL {isolation}; SET search_path=labreserve,public; SET application_name='stage02_race_a'; {first}; SELECT pg_sleep(2); COMMIT;"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+10
        while sql("SELECT count(*) FROM pg_stat_activity WHERE application_name='stage02_race_a' AND wait_event='PgSleep'")!='1':
            if a.poll() is not None: raise RuntimeError(a.communicate())
            if time.monotonic()>deadline: raise RuntimeError('A did not reach locked stage')
            time.sleep(.03)
        b=subprocess.run(PSQL+['-c',f"BEGIN ISOLATION LEVEL {isolation}; SET search_path=labreserve,public; {second}; COMMIT;"],capture_output=True,text=True)
        out,err=a.communicate(timeout=10)
        assert a.returncode==0,err
        if expected=='ok': assert b.returncode==0,b.stderr
        else: assert b.returncode!=0 and expected in b.stderr,b.stderr
        assert sql('SET search_path=labreserve,public; '+check)=='t',label+' invariant'
        results.append({'test':label,'isolation':isolation,'first':'committed','second':expected,'invariant':'PASS','detail':b.stderr.strip()})
        print('PASS:',label,expected)
    finally:
        if a.poll() is None: a.kill(); a.communicate()

base="date_trunc('day',now())+interval '40 days'"
book=lambda offset: f"SELECT create_booking(1,2,1,{base}+interval '{offset} hours',{base}+interval '{offset+1} hours','Race test')"
raw=lambda offset: f"INSERT INTO booking(user_id,equipment_id,capability_id,period,purpose) VALUES(1,2,1,tstzrange({base}+interval '{offset} hours',{base}+interval '{offset+1} hours'),'Raw race')"
block=lambda offset: f"SELECT register_unavailability(3,2,'maintenance',{base}+interval '{offset} hours',{base}+interval '{offset+1} hours','Race maintenance')"
no_overlap="SELECT NOT EXISTS(SELECT 1 FROM booking b JOIN unavailability u USING(equipment_id) WHERE b.status='confirmed' AND lower(b.period)>now() AND u.status<>'cancelled' AND b.period && u.period::tstzrange)"
race('C01 two overlapping bookings',book(0),book(0),'23P01',"SELECT count(*)=1 FROM booking WHERE equipment_id=2 AND status='confirmed' AND purpose='Race test'")
race('C02 outage then booking',block(3),book(3),'23514',no_overlap)
race('C03 booking then outage',book(6),block(6),'ok',no_overlap)
race('C04 direct INSERTs',raw(9),raw(9),'23P01',"SELECT count(*)=1 FROM booking WHERE purpose='Raw race' AND status='confirmed'")
race('C05 stale RR snapshot',block(12),book(12),'40001',no_overlap,'REPEATABLE READ')
# Clean only our test rows by cancellation, retaining audited history.
sql("SET search_path=labreserve,public; SELECT cancel_booking(1,id,'Race cleanup') FROM booking WHERE purpose IN ('Race test','Raw race') AND status IN ('confirmed','needs_transfer')")
Path(os.environ.get('TEST_OUTPUT','output')+'/concurrency.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))

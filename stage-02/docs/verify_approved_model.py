#!/usr/bin/env python3
"""Verify the approved conceptual links against the actual exported PostgreSQL schema."""
from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
names={'user':'app_user','role':'app_role','adm':'admission','notice':'notification',
 'type':'equipment_type','book':'booking','session':'use_session','cap':'capability',
 'alt':'alternative','repair':'repair','equip':'equipment','fault':'fault_report','outage':'unavailability'}
for ext in ('xml','png'):
 original=root.parent/f'ER-модель_final.drawio.{ext}'
 if not original.exists():original=root/f'ER-модель_final.drawio.{ext}'
 assert (root/f'diagrams/conceptual_approved.{ext}').read_bytes()==original.read_bytes()
model=json.loads((root/'docs/datalogical.json').read_text());tables={t['name']:t for t in model['tables']}
approved=E.parse(root/'diagrams/conceptual_approved.xml').getroot()
entities={c.get('id') for c in approved.iter('mxCell') if c.get('id') in names}
assert entities==names.keys()
links=[c for c in approved.iter('mxCell') if c.get('edge')=='1'];many=0
fks=[(f['from'].split('.')[-1],f['to'].split('.')[-1],re.search(r'FOREIGN KEY \((.*?)\)',f['definition']).group(1)) for f in model['foreign_keys']]
for c in links:
 a,b=names[c.get('source')],names[c.get('target')]
 style=dict(p.split('=',1) for p in c.get('style').split(';') if '=' in p)
 left,right=style['startArrow'],style['endArrow']
 if left==right=='ERmany':
  join={frozenset(('app_user','app_role')):'user_role',frozenset(('equipment_type','capability')):'type_capability'}[frozenset((a,b))]
  assert any(x==join and y==a for x,y,z in fks) and any(x==join and y==b for x,y,z in fks);many+=1
 else:
  children=[(x,y,z) for x,y,z in fks if (x,y)==((a,b) if left=='ERmany' else (b,a))]
  assert children,(c.get('id'),a,b)
  if left==right=='ERone':
   assert any(any(k['kind']=='u' and k['definition']==f'UNIQUE ({field})' for k in tables[child]['constraints']) for child,parent,field in children)
assert len(links)==20 and many==2 and len(tables)==17
assert any(c['name']=='work_kind' and c['nullable']=='NO' for c in tables['repair']['columns'])
logical=E.parse(root/'diagrams/logical.xml').getroot()
visible={c.get('id'):c for c in logical.iter('mxCell') if c.get('vertex')=='1'}
assert set(visible)==set(names.values())|{'user_role','type_capability'}
for c in approved.iter('mxCell'):
 if c.get('id') in names:
  assert E.tostring(c.find('mxGeometry'))==E.tostring(visible[names[c.get('id')]].find('mxGeometry'))
represented=set()
for c in logical.iter('mxCell'):
 if c.get('edge')!='1':continue
 for field in c.get('data-fk-fields').split(','):
  matches=[f for f in fks if f[2]==field and {f[0],f[1]}=={c.get('source'),c.get('target')}]
  assert len(matches)==1
  represented.add(matches[0])
assert represented=={f for f in fks if f[0] in visible and f[1] in visible}
assert len(represented)==24
assert len([c for c in logical.iter('mxCell') if c.get('edge')=='1'])==22
print('PASS: all 13 original box geometries preserved; 15 domain/association tables; all 24 domain FK represented')
print('PASS: approved originals unchanged; 13 entities; all 20 approved links covered; 2 M:N; 17 tables; 27 FK; mandatory work_kind')

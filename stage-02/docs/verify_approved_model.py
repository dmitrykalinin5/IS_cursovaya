#!/usr/bin/env python3
"""Verify the approved conceptual links against the actual exported PostgreSQL schema."""
from pathlib import Path
import hashlib,json,re,xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
names={'user':'app_user','role':'app_role','adm':'admission','notice':'notification',
 'type':'equipment_type','book':'booking','session':'use_session','cap':'capability',
 'alt':'alternative','repair':'repair','equip':'equipment','fault':'fault_report','outage':'unavailability'}
for ext in ('xml','png'):
 assert (root/f'diagrams/conceptual_approved.{ext}').read_bytes()==(root.parent/f'ER-модель_final.drawio.{ext}').read_bytes()
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
assert len([c for c in logical.iter('mxCell') if c.get('edge')=='1'])==len(fks)==27
print('PASS: approved originals unchanged; 13 entities; all 20 approved links covered; 2 M:N; 17 tables; 27 FK; mandatory work_kind')

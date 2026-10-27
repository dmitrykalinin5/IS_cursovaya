#!/usr/bin/env python3
"""Build the editable physical schema from PostgreSQL's exported catalogue."""
import html,json,re
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
model=json.loads((root/'docs/datalogical.json').read_text())
tables={t['name']:t for t in model['tables']}
# Space for every column; technical logs are visibly separated in the last row.
positions={
 'app_role':(0,0),'user_role':(560,0),'app_user':(1120,0),'admission':(1680,0),
 'capability':(0,660),'type_capability':(560,660),'equipment_type':(1120,660),'equipment':(1680,660),
 'notification':(0,1320),'booking':(560,1320),'alternative':(1120,1320),'use_session':(1680,1320),
 'fault_report':(0,1980),'unavailability':(560,1980),'repair':(1120,1980),
 'audit_event':(560,2640),'conflict_event':(1120,2640)}
mx=E.Element('mxfile',host='app.diagrams.net'); page=E.SubElement(mx,'diagram',id='logical',name='Даталогическая модель')
g=E.SubElement(page,'mxGraphModel',grid='1',gridSize='10',page='1',pageWidth='2850',pageHeight='3400')
r=E.SubElement(g,'root');E.SubElement(r,'mxCell',id='0');E.SubElement(r,'mxCell',id='1',parent='0')
positions={name:(x/560*650+100,y+160) for name,(x,y) in positions.items()}
heights={}
for name,(x,y) in positions.items():
 t=tables[name]; keys={}
 for c in t['constraints']:
  if c['kind'] in ('p','f'):
   cols=re.search(r'\(([^)]+)\)',c['definition']).group(1).split(', ')
   for col in cols: keys.setdefault(col,[]).append('PK' if c['kind']=='p' else 'FK')
 rows=[]
 for c in t['columns']:
  typ=c.get('domain') or c['udt']; tags=','.join(keys.get(c['name'],[]))
  nn=' NN' if c['nullable']=='NO' else ' NULL'
  rows.append(html.escape(f"{c['name']} : {typ} {tags}{nn}"))
 color='#FFF1DB' if name in ('audit_event','conflict_event') else '#EDF3FC'
 body='<b>'+name+'</b>'+('<br><i>Служебный журнал</i>' if name in ('audit_event','conflict_event') else '')+'<hr>'+'<br>'.join(rows)
 c=E.SubElement(r,'mxCell',id=name,parent='1',vertex='1',value=body,style=f'rounded=1;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacing=16;fontSize=19;fillColor={color};strokeColor=#334155;')
 E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width='480',height=str(85+len(rows)*29),attrib={'as':'geometry'})
 heights[name]=85+len(rows)*29
source_uses={};target_uses={}
for i,fk in enumerate(model['foreign_keys']):
 src=fk['from'].split('.')[-1]; dst=fk['to'].split('.')[-1]
 field=re.search(r'FOREIGN KEY \((.*?)\)',fk['definition']).group(1)
 null=next(c['nullable']=='YES' for c in tables[src]['columns'] if c['name']==field)
 unique=any(c['kind']=='u' and c['definition']==f'UNIQUE ({field})' for c in tables[src]['constraints'])
 style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;jumpStyle=arc;jumpSize=10;fontSize=17;labelBackgroundColor=#FFFFFF;strokeColor=#64748B;startSize=18;endSize=18;'
 style+='startArrow='+('ERzeroToOne' if null else 'ERone')+';endArrow='+('ERzeroToOne' if unique else 'ERzeroToMany')+';'
 source_uses[dst]=source_uses.get(dst,0)+1;target_uses[src]=target_uses.get(src,0)+1
 sy=.12+source_uses[dst]*.07;ty=.15+target_uses[src]*.13
 style+=f'exitX=1;exitY={sy};entryX=0;entryY={ty};exitPerimeter=0;entryPerimeter=0;'
 c=E.SubElement(r,'mxCell',id=f'fk-{i}',parent='1',edge='1',source=dst,target=src,value=field,style=style)
 geo=E.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
 points=E.SubElement(geo,'Array',attrib={'as':'points'})
 px,py=positions[dst];cx,cy=positions[src]
 lane1=px+480+25+(i%6)*17;lane2=cx-25-(i%6)*17
 band=cy-35-(i%5)*20
 for x,y in [(lane1,py+heights[dst]*sy),(lane1,band),(lane2,band),(lane2,cy+heights[src]*ty)]:
  E.SubElement(points,'mxPoint',x=str(x),y=str(y))
for ext in ('drawio','xml'):
 E.ElementTree(mx).write(root/f'diagrams/logical.{ext}',encoding='utf-8',xml_declaration=True)
print(f'logical.drawio/xml: {len(tables)} tables, {len(model["foreign_keys"])} FK')

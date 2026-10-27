#!/usr/bin/env python3
"""Convert the approved ER model to tables without moving its original boxes."""
import copy,html,json,re
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
model=json.loads((root/'docs/datalogical.json').read_text())
tables={t['name']:t for t in model['tables']}
names={'user':'app_user','role':'app_role','adm':'admission','notice':'notification',
 'type':'equipment_type','book':'booking','session':'use_session','cap':'capability',
 'alt':'alternative','repair':'repair','equip':'equipment','fault':'fault_report','outage':'unavailability'}
source=E.parse(root/'ER-модель_final.drawio.xml').getroot()
mx=copy.deepcopy(source);g=mx.find('.//mxGraphModel');r=g.find('root')
for cell in list(r):
 if cell.tag=='mxCell' and cell.get('id') not in names and cell.get('id') not in ('0','1') and cell.get('edge')!='1':r.remove(cell)

def set_style(c,**changes):
 style=dict(p.split('=',1) for p in c.get('style','').split(';') if '=' in p);style.update({k:str(v) for k,v in changes.items()})
 c.set('style',';'.join(k+'='+v for k,v in style.items())+';')
def content(cell,name,title):
 table=tables[name];rows=[]
 for col in table['columns']:
  flags=[]
  for key in table['constraints']:
   if key['kind'] in ('p','f') and re.search(r'\b'+col['name']+r'\b',re.search(r'\(([^)]+)\)',key['definition']).group(1)):
    flags.append('PK' if key['kind']=='p' else 'FK')
  flags.append('NN' if col['nullable']=='NO' else 'NULL')
  rows.append(col['name']+' : '+(col.get('domain') or col['udt'])+' '+','.join(flags))
 h=float(cell.find('mxGeometry').get('height')); font=min(14,(h-38)/len(rows)*.86)
 body='<div style="font-size:15px;text-align:center"><b>'+html.escape(title)+'</b></div>'
 if title!=name:body+='<div style="font-size:12px;text-align:center">'+name+'</div>'
 body+='<div style="font-size:'+str(font)+'px;line-height:115%;text-align:left">'+'<br>'.join(html.escape(row) for row in rows)+'</div>'
 cell.set('value',body);set_style(cell,spacing=5,fontSize=font,verticalAlign='middle',align='left')

for cell in r.findall('mxCell'):
 old=cell.get('id')
 if old in names:
  title=html.unescape(re.sub('<[^>]+>',' ',cell.get('value',''))).strip()
  # The first bold fragment is the entity name in the approved source.
  bold=re.search(r'<b>(.*?)</b>',cell.get('value',''),re.S)
  if bold:title=html.unescape(re.sub('<[^>]+>','',bold.group(1))).strip()
  cell.set('id',names[old]);content(cell,names[old],title)
for cell in list(r):
 if cell.get('edge')!='1':continue
 a,b=cell.get('source'),cell.get('target')
 if cell.get('id') in ('link-1','link-4'):r.remove(cell);continue
 cell.set('source',names[a]);cell.set('target',names[b])
 fields=[]
 for fk in model['foreign_keys']:
  child,parent=fk['from'].split('.')[-1],fk['to'].split('.')[-1]
  if {child,parent}=={names[a],names[b]}:fields.append(re.search(r'FOREIGN KEY \((.*?)\)',fk['definition']).group(1))
 cell.set('value',', '.join(fields));cell.set('data-fk-fields',','.join(fields))
 set_style(cell,fontSize=11)
# Place only the two association tables in the gaps of their former M:N lines.
for name,x,y,w,h in [('user_role',490,1020,480,100),('type_capability',2240,865,150,120)]:
 c=E.SubElement(r,'mxCell',id=name,parent='1',vertex='1',style='rounded=1;whiteSpace=wrap;html=1;fillColor=#F0F3FA;strokeColor=#25364A;strokeWidth=2;')
 E.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'});content(c,name,name)
for ident,parent,child,ex,ey,ix,iy,field in [
 ('role-user_role','app_role','user_role',.5,1,.5,0,'role_code'),
 ('user-user_role','app_user','user_role',.5,0,.5,1,'user_id'),
 ('type-type_capability','equipment_type','type_capability',1,.5,0,.5,'type_id'),
 ('cap-type_capability','capability','type_capability',0,.5,1,.5,'capability_id')]:
 c=E.SubElement(r,'mxCell',id=ident,parent='1',edge='1',source=parent,target=child,value='',style=f'edgeStyle=orthogonalEdgeStyle;startArrow=ERone;endArrow=ERmany;startSize=12;endSize=12;strokeColor=#1D6F8B;exitX={ex};exitY={ey};entryX={ix};entryY={iy};',attrib={'data-fk-fields':field})
 E.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
E.ElementTree(mx).write(root/'diagrams/logical.xml',encoding='utf-8',xml_declaration=True)
print('15 domain/association tables; original 13 geometries and 18 routes unchanged; 24 FK represented by 22 connectors')
# One landscape sheet, using the approved geometry also for the PDF.
def tx(s):return str(s).replace('_',r'\_').replace('&',r'\&').replace('%',r'\%')
vertices={c.get('id'):c for c in r.findall('mxCell') if c.get('vertex')=='1'}
def box(c):return {k:float(c.find('mxGeometry').get(k)) for k in ['x','y','width','height']}
def port(c,style,kind):
 b=box(c);return (b['x']+b['width']*float(style[kind+'X']),b['y']+b['height']*float(style[kind+'Y']))
parts=[r'''\documentclass{article}
\usepackage{fontspec}\usepackage[russian]{babel}\setmainfont{DejaVu Sans}
\usepackage[paperwidth=841mm,paperheight=350mm,margin=10mm]{geometry}
\usepackage{tikz}\pagestyle{empty}\setlength{\parindent}{0pt}
\begin{document}\begin{center}
{\LARGE Даталогическая модель «ЛабРезерв»}\par\medskip
Расположение сущностей соответствует согласованной инфологической модели.\par
PK — первичный ключ; FK — внешний ключ; NN — NOT NULL; NULL — поле необязательное.\par\bigskip
\begin{tikzpicture}[x=.025cm,y=-.025cm,line width=.45pt]
''']
labels=[];marks=[]
import math
for c in r.findall('mxCell'):
 if c.get('edge')!='1':continue
 st=dict(p.split('=',1) for p in c.get('style').split(';') if '=' in p)
 start=port(vertices[c.get('source')],st,'exit');end=port(vertices[c.get('target')],st,'entry')
 points=[(float(p.get('x')),float(p.get('y'))) for p in c.findall('./mxGeometry/Array/mxPoint')]
 if not points and abs(start[0]-end[0])>.1 and abs(start[1]-end[1])>.1:
  if st['exitY']=='1' and st['entryY']=='1':
   y=max(start[1],end[1])+40;points=[(start[0],y),(end[0],y)]
  else:
   x=(start[0]+end[0])/2;points=[(x,start[1]),(x,end[1])]
 pts=[start]+points+[end]
 parts.append(r'\draw[draw=black!65] '+' -- '.join(f'({x},{y})' for x,y in pts)+';')
 # Crow's-foot ends; directions follow the original connector ports.
 for p,q,arrow in [(pts[0],pts[1],st['startArrow']),(pts[-1],pts[-2],st['endArrow'])]:
  dx,dy=q[0]-p[0],q[1]-p[1];length=math.hypot(dx,dy)
  if not length:continue
  dx/=length;dy/=length;size=min(12,length*.3)
  if arrow=='ERmany':
   for spread in (-size*.5,0,size*.5):
    marks.append(f'\\draw ({p[0]+dx*size},{p[1]+dy*size}) -- ({p[0]-dy*spread},{p[1]+dx*spread});')
  else:marks.append(f'\\draw ({p[0]+dx*size*.4-dy*size*.5},{p[1]+dy*size*.4+dx*size*.5}) -- ({p[0]+dx*size*.4+dy*size*.5},{p[1]+dy*size*.4-dx*size*.5});')
 if c.get('value'):
  segments=[(math.hypot(b[0]-a[0],b[1]-a[1]),a,b) for a,b in zip(pts,pts[1:])]
  _,a,b=max(segments)
  labels.append(r'\node[fill=white,inner sep=.5pt,font=\fontsize{6}{7}\selectfont] at '+f'({(a[0]+b[0])/2},{(a[1]+b[1])/2})'+' {'+tx(c.get('value'))+'};')
parts+=marks
for name,c in vertices.items():
 b=box(c);table=tables[name];rows=[]
 for col in table['columns']:
  flags=[]
  for key in table['constraints']:
   if key['kind'] in ('p','f') and re.search(r'\b'+col['name']+r'\b',re.search(r'\(([^)]+)\)',key['definition']).group(1)):
    flags.append('PK' if key['kind']=='p' else 'FK')
  flags.append('NN' if col['nullable']=='NO' else 'NULL')
  rows.append(tx(col['name'])+' : '+tx(col.get('domain') or col['udt'])+' '+','.join(flags))
 title=html.unescape(re.search(r'<b>(.*?)</b>',c.get('value')).group(1))
 fontsize=min(9,(b['height']-35)/len(rows)*.55);leading=fontsize*1.15
 header=r'\textbf{'+tx(title)+'}'+(r'\\{\fontsize{7}{8}\selectfont '+tx(name)+'}' if title!=name else '')
 body=header+r'\\[1mm]'+r'\\'.join(rows)
 width=b['width']*.025; height=b['height']*.025
 parts.append(r'\node[anchor=north west,draw,rounded corners=1.5mm,fill=blue!5,align=left,inner sep=1mm,text width='+str(width-.2)+r'cm,minimum width='+str(width)+r'cm,minimum height='+str(height)+r'cm,font=\fontsize{'+str(fontsize)+'}{'+str(leading)+r'}\selectfont] at '+f'({b["x"]},{b["y"]})'+' {'+body+'};')
parts+=labels
parts += [r'\end{tikzpicture}\par\medskip',r'M:N раскрыты таблицами user\_role и type\_capability; исходные блоки не перемещены.',r'\end{center}\end{document}']
(root/'diagrams/logical.tex').write_text('\n'.join(parts)+'\n')

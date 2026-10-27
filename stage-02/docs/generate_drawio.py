#!/usr/bin/env python3
"""Render the current editable logical.xml to TEX; never overwrite manual XML edits."""
import html,json,re
from pathlib import Path
import xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[1]
model=json.loads((root/'docs/datalogical.json').read_text())
tables={t['name']:t for t in model['tables']}
source=E.parse(root/'diagrams/logical.xml').getroot()
r=source.find('.//mxGraphModel/root')
if r is None and source.tag=='mxGraphModel':r=source.find('root')
def column_rows(name):
 rows=[]
 for col in tables[name]['columns']:
  flags=[]
  for key in tables[name]['constraints']:
   if key['kind'] in ('p','f') and re.search(r'\b'+col['name']+r'\b',re.search(r'\(([^)]+)\)',key['definition']).group(1)):
    flags.append('PK' if key['kind']=='p' else 'FK')
  rows.append((col['name'],col.get('domain') or col['udt'],flags,col['nullable']=='YES'))
 return rows

# One landscape sheet using the current XML geometry, ports and routes.
def tx(s):return str(s).replace('_',r'\_').replace('&',r'\&').replace('%',r'\%')
vertices={c.get('id'):c for c in r.findall('mxCell') if c.get('vertex')=='1'}
def box(c):return {k:float(c.find('mxGeometry').get(k)) for k in ['x','y','width','height']}
def port(c,style,kind):
 b=box(c);return (b['x']+b['width']*float(style[kind+'X']),b['y']+b['height']*float(style[kind+'Y']))
parts=[r'''\documentclass{article}
\usepackage{fontspec}\usepackage[russian]{babel}\setmainfont{DejaVu Sans}
\usepackage[paperwidth=841mm,paperheight=350mm,margin=10mm]{geometry}
\usepackage[table]{xcolor}\usepackage{tikz}\pagestyle{empty}\setlength{\parindent}{0pt}
\begin{document}\begin{center}
{\LARGE Даталогическая модель «ЛабРезерв»}\par\medskip
Даталогическая схема по редактируемому исходнику logical.xml.\par
PK — первичный ключ (жёлтый); FK — внешний ключ (голубой); NULL: «да» — поле необязательное, «нет» — обязательное.\par\bigskip
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
 b=box(c);rows=column_rows(name);narrow=b['width']<250
 title=html.unescape(re.search(r'<b>(.*?)</b>',c.get('value')).group(1))
 width=b['width']*.025;height=b['height']*.025
 fontsize=min(10,(height*28.35-30)/(len(rows)+1)/1.3)
 if narrow:fontsize=7
 leading=fontsize*1.10
 header=r'\textbf{'+tx(title)+'}'+(r' {\fontsize{7}{8}\selectfont '+tx(name)+'}' if title!=name else '')
 widths=[(width-.52)*ratio for ratio in [.13,.45,.30,.12]]
 spec=''.join('p{'+str(w)+'cm}' for w in widths)
 body=header+r'\\[1mm]\begingroup\setlength{\tabcolsep}{.4mm}\begin{tabular}{'+('p{'+str(width-.28)+'cm}' if narrow else spec)+'}'
 if not narrow:body+=r'\rowcolor{blue!6}Ключ & Атрибут & Тип & NULL \\ '
 for field,typ,flags,nullable in rows:
  color='yellow!24' if 'PK' in flags else 'blue!9' if 'FK' in flags else 'white'
  keys=' '.join(r'\textcolor{'+('brown' if flag=='PK' else 'blue!65!black')+r'}{\textbf{'+flag+'}}' for flag in flags) or '—'
  body+=r'\rowcolor{'+color+'}'
  if narrow:body+=r'\textbf{'+tx(field)+r'} \newline '+tx(typ)+' '+keys+r' \\ '
  else:body+=keys+r' & \textbf{'+tx(field)+'} & '+tx(typ)+' & '+('да' if nullable else 'нет')+r' \\ '
 body+=r'\end{tabular}\endgroup'
 parts.append(r'\node[anchor=north west,draw,rounded corners=1.5mm,fill=white,align=left,inner sep=1mm,text width='+str(width-.2)+r'cm,minimum width='+str(width)+r'cm,minimum height='+str(height)+r'cm,font=\fontsize{'+str(fontsize)+'}{'+str(leading)+r'}\selectfont] at '+f'({b["x"]},{b["y"]})'+' {'+body+'};')

parts+=labels
parts += [r'\end{tikzpicture}\par\medskip',r'M:N раскрыты таблицами user\_role и type\_capability; исходные блоки не перемещены.',r'\end{center}\end{document}']
(root/'diagrams/logical.tex').write_text('\n'.join(parts)+'\n')

print('Rendered current logical.xml to logical.tex; XML unchanged')

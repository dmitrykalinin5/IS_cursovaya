#!/usr/bin/env python3
"""Generate dictionary and editable diagrams from the verified PostgreSQL export."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'docs/datalogical.json').read_text())
tables={t['name']:t for t in m['tables']}
purpose={
'app_user':'Учётная запись человека; активность и профиль',
'app_role':'Три внешние роли предметной области',
'user_role':'Назначение ролей пользователям (M:N)',
'equipment_type':'Тип оборудования и архивирование',
'capability':'Справочник требуемых функций',
'type_capability':'Поддерживаемые типом функции (M:N)',
'equipment':'Инвентарная единица, характеристики, архив',
'admission':'Допуск к типу; период, основание, автор и отзыв',
'booking':'Плановый интервал, владелец, цель и жизненный цикл',
'alternative':'Предложение переноса: интервал, приоритет и статус',
'fault_report':'Первичное сообщение и результат проверки',
'unavailability':'Техническое событие: ТО либо подтверждённая неисправность',
'repair':'Техническая работа: вид, исполнитель, интервал и результат',
'use_session':'Фактические начало и окончание работы',
'notification':'Внутрисистемное уведомление и прочтение',
'audit_event':'Служебный журнал значимых изменений (вне инфологической модели)',
'conflict_event':'Служебный журнал отказов для статистики (вне инфологической модели)'}
(root/'docs/entities.json').write_text(json.dumps(purpose,ensure_ascii=False,indent=2))
def tex(s):
    chars={'\\':r'\textbackslash{}','_':r'\_\allowbreak{}','%':r'\%','&':r'\&','#':r'\#','{':r'\{','}':r'\}'}
    return ''.join(chars.get(c,c) for c in str(s))
# Complete portable dictionary, including every FK action and CHECK.
md=['# Даталогическая модель: словарь данных','', 'Экспорт фактической PostgreSQL-схемы. Все FK: RESTRICT при удалении и обновлении.', '']
texparts=[]
for name in purpose:
    t=tables[name]
    md += [f'## `{name}` — {purpose[name]}','', '| Столбец | Тип | NULL | Значение по умолчанию |','|---|---|---|---|']
    texparts += [r'\par\noindent\begin{minipage}{\linewidth}',r'\subsection{'+tex(name)+'}', tex(purpose[name])+r'.\par\smallskip\noindent',r'\begin{tabular}{p{0.29\textwidth}p{0.25\textwidth}p{0.1\textwidth}p{0.25\textwidth}}',r'\toprule Столбец & Тип & NULL & По умолчанию \\ \midrule']
    for c in t['columns']:
        typ=c.get('domain') or (c['udt'] if c['type']=='USER-DEFINED' else c['type'])
        typ={'timestamp with time zone':'timestamptz'}.get(typ,typ)
        default='IDENTITY' if c['identity']=='YES' else c['default'] or '—'
        md.append(f"| `{c['name']}` | `{typ}` | {c['nullable']} | `{default}` |")
        texparts.append(tex(c['name'])+' & '+tex(typ)+' & '+('да' if c['nullable']=='YES' else 'нет')+' & '+tex(default)+r' \\')
    md += ['', 'Ограничения:', '']
    texparts += [r'\bottomrule\end{tabular}\end{minipage}\par',r'\begin{itemize}']
    for c in t['constraints']:
        md.append(f"- `{c['name']}`: `{c['definition']}`.")
        # Keep SQL expressions as line-breakable text, monospaced snippets in appendix separately.
        if c['kind']!='n':texparts.append(r'\item '+tex(c['definition'])+'.')
    texparts.append(r'\end{itemize}')
    md.append('')
(root/'docs/DATA_DICTIONARY.md').write_text('\n'.join(md))
(root/'docs/dictionary.tex').write_text('\n'.join(texparts))
# Full ER Mermaid source: real key/FK relations, not an image-only asset.
er=['erDiagram']
for name,t in tables.items():
    er.append(f'  {name} {{')
    pk=' '.join(c['definition'] for c in t['constraints'] if c['kind']=='p')
    fk=' '.join(c['definition'] for c in t['constraints'] if c['kind']=='f')
    for c in t['columns']:
        typ=c['udt'] if c['type']=='USER-DEFINED' else c['type'].replace(' ','_')
        flag=' PK' if re.search(r'\b'+c['name']+r'\b',pk) else ' FK' if re.search(r'\b'+c['name']+r'\b',fk) else ''
        er.append(f"    {typ} {c['name']}{flag}")
    er.append('  }')
for fk in m['foreign_keys']:
    src=fk['from'].split('.')[-1]; dst=fk['to'].split('.')[-1]
    field=re.search(r'FOREIGN KEY \((.*?)\)',fk['definition']).group(1)
    nullable=next(c['nullable']=='YES' for c in tables[src]['columns'] if c['name']==field)
    unique=any(c['kind']=='u' and c['definition']==f'UNIQUE ({field})' for c in tables[src]['constraints'])
    er.append(f'  {dst} '+('o|' if nullable else '||')+'--'+('o|' if unique else 'o{')+f' {src} : "{field}"')
(root/'diagrams/logical.mmd').write_text('\n'.join(er)+'\n')
# The approved XML is the source of the conceptual graph; technical logs are excluded.
import xml.etree.ElementTree as ET
approved=ET.parse(root/'diagrams/conceptual_approved.xml').getroot()
entity_map={'user':'app_user','role':'app_role','adm':'admission','notice':'notification',
 'type':'equipment_type','book':'booking','session':'use_session','cap':'capability',
 'alt':'alternative','repair':'repair','equip':'equipment','fault':'fault_report','outage':'unavailability'}
con=['erDiagram']
for cell in approved.iter('mxCell'):
    if cell.get('id') in entity_map:
        name=entity_map[cell.get('id')]
        con += [f'  {name} {{']+[f"    {c['udt']} {c['name']}" for c in tables[name]['columns']]+['  }']
    if cell.get('edge')=='1':
        style=dict(part.split('=',1) for part in cell.get('style','').split(';') if '=' in part)
        left='}o' if style['startArrow']=='ERmany' else '||'
        right='o{' if style['endArrow']=='ERmany' else '||'
        con.append(f"  {entity_map[cell.get('source')]} {left}--{right} {entity_map[cell.get('target')]} : связь")
(root/'diagrams/conceptual.mmd').write_text('\n'.join(con)+'\n')
# Vector rendering: three thematic sheets with every table and every FK.
groups=[['app_user','app_role','equipment_type','capability','user_role','equipment','type_capability','admission'],
        ['booking','alternative','use_session','notification','conflict_event'],
        ['fault_report','unavailability','repair','audit_event']]
header=r'''\documentclass[a4paper,landscape,10pt]{article}
\usepackage{fontspec}\usepackage[russian]{babel}\setmainfont{DejaVu Sans}
\usepackage[margin=1cm]{geometry}\usepackage{tikz}
\usetikzlibrary{arrows.meta}\pagestyle{empty}\setlength{\parindent}{0pt}
\tikzset{tbl/.style={draw,fill=blue!5,text width=5.4cm,align=left,font=\fontsize{8}{11}\selectfont,inner sep=7pt},fk/.style={-Latex,thick},lab/.style={fill=white,font=\scriptsize,inner sep=2pt}}
\begin{document}
'''
parts=[header]
for gi,group in enumerate(groups):
    if gi:parts.append(r'\newpage')
    parts.append(r'\begin{center}\Large Даталогическая модель: '+['каталог и допуски','бронирование и использование','технические работы и аудит'][gi]+r'\end{center}')
    parts.append('PK — первичный ключ; FK — внешний ключ; NN — NOT NULL. Стрелка направлена от FK к родителю. Все FK: RESTRICT / RESTRICT.')
    parts.append(r'\begin{center}\begin{tikzpicture}')
    for i,name in enumerate(group):
        t=tables[name]; x=(i%4)*6.6; y=-(i//4)*7.6
        if gi==1: x,y={'booking':(6.6,0),'alternative':(0,-7.6),'use_session':(6.6,-7.6),'notification':(13.2,-7.6),'conflict_event':(19.8,0)}[name]
        if gi==2: x,y={'fault_report':(0,0),'unavailability':(6.6,-7.6),'repair':(13.2,0),'audit_event':(19.8,0)}[name]
        pk=' '.join(c['definition'] for c in t['constraints'] if c['kind']=='p')
        fks={re.search(r'FOREIGN KEY \((.*?)\)',c['definition']).group(1): re.search(r'REFERENCES ([\w.]+)',c['definition']).group(1).split('.')[-1] for c in t['constraints'] if c['kind']=='f'}
        body=[r'\textbf{'+tex(name)+'}'+r'\\\hrulefill\\']
        for c in t['columns']:
            tags=[]
            if re.search(r'\b'+c['name']+r'\b',pk):tags.append('PK')
            if c['name'] in fks:tags.append('FK')
            if c['nullable']=='NO':tags.append('NN')
            typ=c['udt'] if c['type']=='USER-DEFINED' else {'timestamp with time zone':'timestamptz','boolean':'bool','character varying':'varchar'}.get(c['type'],c['type'])
            body.append(tex(c['name'])+' : '+tex(typ)+' '+','.join(tags)+r'\\')
        parts.append(f'\\node[tbl] ({name}) at ({x},{y}) '+'{'+'\n'.join(body)+'};')
    # Only local lines; references outside sheet listed below, so no cross-sheet ambiguity.
    for fk in m['foreign_keys']:
        src=fk['from'].split('.')[-1];dst=fk['to'].split('.')[-1]
        if src not in group or dst not in group:continue
        field=re.search(r'FOREIGN KEY \((.*?)\)',fk['definition']).group(1)
        # Keep arrows in wide vertical/horizontal gaps with short column labels.
        parts.append(f'\\draw[fk] ({src}) -- ({dst});')
    parts.append(r'\end{tikzpicture}\end{center}')
    outside=[]
    for fk in m['foreign_keys']:
        src=fk['from'].split('.')[-1]; dst=fk['to'].split('.')[-1]
        if src in group:
            field=re.search(r'FOREIGN KEY \((.*?)\)',fk['definition']).group(1)
            outside.append(tex(src+'.'+field)+' → '+tex(dst+'.id'))
    if outside:parts.append(r'\small\raggedright Все FK листа (включая внешние): '+r'; \allowbreak '.join(outside)+'.')
parts.append(r'\end{document}')
(root/'diagrams/logical.tex').write_text('\n'.join(parts))

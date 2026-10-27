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
# A single full diagram is generated together with the draw.io source.
import subprocess,sys
subprocess.run([sys.executable,str(root/'docs/generate_drawio.py')],check=True)

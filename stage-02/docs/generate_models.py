#!/usr/bin/env python3
"""Generate the dictionary and the current editable diagram from the verified PostgreSQL export."""
import json
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
# Render the current draw.io source without overwriting manual edits.
import subprocess,sys
subprocess.run([sys.executable,str(root/'docs/generate_drawio.py')],check=True)

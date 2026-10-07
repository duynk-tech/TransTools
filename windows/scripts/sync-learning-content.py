"""Mirror the literal curated macOS learning content; fail if its structure changes."""
from pathlib import Path
import json, re
root = Path(__file__).resolve().parents[2]
source = (root / 'Sources/TransTools/LanguageLearning.swift').read_text()
quoted = r'"(?:\\.|[^"\\])*"'
def fields(text):
    return {key: json.loads(value) for key,value in re.findall(r'(\w+):\s*('+quoted+r')',text)}
lang = {'english':'en','japanese':'ja','chinese':'zh','korean':'ko'}
daily=[]
section=source[source.index('public func getSentenceOfTheDay()'):source.index('// Curated Starter Cards')]
for name,body in re.findall(r'case \.(\w+):(.*?)(?=case \.|\n        }\n)',section,re.S):
    row=fields(body); row['Language']=lang[name]; daily.append(row)
starters=[]
section=source[source.index('public func seedStarterVocabulary()'):source.index('// Communication Scenarios')]
for body in re.findall(r'vocab.add\((.*?)\)\n',section,re.S):
    row=fields(body); starters.append({'Word':row['word'],'Meaning':row['meaning'],'Phonetic':row['phonetic'],'ExampleSentence':row['context'],'LanguageCode':row['language']})
scenarios=[]
section=source[source.index('public func getScenarios()'):source.index('// MARK: - Main Language Learning Dashboard View')]
for body in re.findall(r'CommunicationScenario\((.*?)\n                \)',section,re.S):
    head,dialogues=body.split('dialogues:',1); row=fields(head); row['Language']=row['id'].split('_')[0]
    row['Dialogues']=[fields(line) for line in re.findall(r'ScenarioDialogue\((.*?)\)\s*[,\n]',dialogues,re.S)]
    scenarios.append(row)
assert len(daily)==4 and len(starters)==20 and len(scenarios)==7
assert all(row['Dialogues'] for row in scenarios)
output=root/'windows/TransTools/Resources/Learning/curated.json'
output.write_text(json.dumps({'Daily':daily,'Starters':starters,'Scenarios':scenarios},ensure_ascii=False,indent=2)+'\n')
print('Synced 4 daily sentences, 20 starter words and 7 communication scenarios.')

#!/usr/bin/env python3
"""Parse the OpenStep project and validate source/target/scheme references."""
from pathlib import Path
import plistlib,re,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent.parent
source=(ROOT/'ZeroRed.xcodeproj/project.pbxproj').read_text()
source=re.sub(r'/\*.*?\*/|^\s*//[^\n]*','',source,flags=re.S|re.M)
tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',source)
pos=0

def take(expected=None):
    global pos
    token=tokens[pos];pos+=1
    if expected is not None: assert token==expected, (expected,token,pos)
    return token

def value():
    token=take()
    if token=='{':
        result={}
        while tokens[pos]!='}':
            key=take().strip('"'); take('='); item=value(); take(';')
            assert key not in result, f'Duplicate key: {key}'
            result[key]=item
        take('}');return result
    if token=='(':
        result=[]
        while tokens[pos]!=')':
            result.append(value())
            if tokens[pos]!=')': take(',')
        take(')');return result
    return token[1:-1] if token.startswith('"') else token

project=value();assert pos==len(tokens)
objects=project['objects']
assert objects[project['rootObject']]['isa']=='PBXProject'
for token in tokens:
    if re.fullmatch('[A-F0-9]{24}',token): assert token in objects, f'Unresolved reference: {token}'
project_obj=objects[project['rootObject']]
targets=[objects[item] for item in project_obj['targets']]
assert {t['name'] for t in targets}=={'ZeroRed','ZeroRedUITests'}
for target,folder in [(next(t for t in targets if t['name']=='ZeroRed'),'ZeroRed'),(next(t for t in targets if t['name']=='ZeroRedUITests'),'UITests')]:
    phases=[objects[p] for p in target['buildPhases']]
    phase=next(p for p in phases if p['isa']=='PBXSourcesBuildPhase')
    paths=[objects[objects[f]['fileRef']]['path'] for f in phase['files']]
    assert set(paths)=={p.name for p in (ROOT/folder).glob('*.swift')}
    for name in paths: assert (ROOT/folder/name).is_file()
info=plistlib.loads((ROOT/'ZeroRed/Info.plist').read_bytes())
assert info['CFBundleDisplayName']=='zero red'
assert info['CFBundleLocalizations']==['en','zh-Hans']
assert info['NSAppTransportSecurity']['NSAllowsLocalNetworking'] is True
scheme=ET.parse(ROOT/'ZeroRed.xcodeproj/xcshareddata/xcschemes/ZeroRed.xcscheme')
for buildable in scheme.iter('BuildableReference'):
    assert objects[buildable.attrib['BlueprintIdentifier']]['isa']=='PBXNativeTarget'
assert len(list(scheme.iter('TestableReference')))==1
print(f'PASS: parsed OpenStep project ({len(objects)} objects), app/UI-test sources, shared scheme and Info.plist')

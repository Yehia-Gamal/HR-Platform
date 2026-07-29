import os, re

src = 'src'
all_files = []
for root, dirs, files in os.walk(src):
    for f in files:
        if f.endswith(('.ts', '.tsx')):
            full = os.path.join(root, f).replace(os.sep, '/')
            all_files.append(full)

# Build set of resolvable modules (without extension)
resolvable = set()
for fp in all_files:
    resolvable.add(fp)
    base = re.sub(r'\.(tsx?|js)$', '', fp)
    resolvable.add(base)
    if fp.endswith('/index.ts') or fp.endswith('/index.tsx'):
        resolvable.add(os.path.dirname(fp))

import_pattern = re.compile(r'''from\s+['"](\.[^'"]+)['"]''')

broken = []
for fp in all_files:
    dir_of_file = os.path.dirname(fp)
    with open(fp, 'r', encoding='utf-8') as fh:
        for lineno, line in enumerate(fh, 1):
            m = import_pattern.search(line)
            if m:
                imp = m.group(1)
                resolved = os.path.normpath(os.path.join(dir_of_file, imp)).replace(os.sep, '/')
                found = False
                for candidate in [resolved, resolved+'.ts', resolved+'.tsx', resolved+'/index.ts', resolved+'/index.tsx']:
                    if candidate in resolvable or os.path.isfile(candidate):
                        found = True
                        break
                if not found:
                    broken.append(f'{fp}:{lineno}: {imp} -> {resolved}')

if broken:
    print('BROKEN IMPORTS:')
    for b in broken:
        print(b)
else:
    print('No broken imports found.')

import os, re, collections

src = 'src'
all_files = []
for root, dirs, files in os.walk(src):
    for f in files:
        if f.endswith(('.ts', '.tsx')):
            full = os.path.join(root, f).replace(os.sep, '/')
            all_files.append(full)

# Collect all exported names per file
export_pattern = re.compile(r'export\s+(?:const|function|class|type|interface|enum|let|var)\s+(\w+)')
export_default_pattern = re.compile(r'export\s+default\s+(?:function|class)\s+(\w+)')
export_brace_pattern = re.compile(r'export\s*\{([^}]+)\}')

exports = {}  # name -> list of files
for fp in all_files:
    with open(fp, 'r', encoding='utf-8') as fh:
        content = fh.read()
    for m in export_pattern.finditer(content):
        name = m.group(1)
        exports.setdefault(name, []).append(fp)
    for m in export_default_pattern.finditer(content):
        name = m.group(1)
        exports.setdefault(name, []).append(fp)
    for m in export_brace_pattern.finditer(content):
        for item in m.group(1).split(','):
            item = item.strip()
            if ' as ' in item:
                item = item.split(' as ')[1].strip()
            if item:
                exports.setdefault(item, []).append(fp)

# Collect all imported names
import_name_pattern = re.compile(r'import\s+\{([^}]+)\}\s+from')
import_default_pattern = re.compile(r'import\s+(\w+)\s+from')

imported = set()
for fp in all_files:
    with open(fp, 'r', encoding='utf-8') as fh:
        content = fh.read()
    for m in import_name_pattern.finditer(content):
        for item in m.group(1).split(','):
            item = item.strip()
            if ' as ' in item:
                item = item.split(' as ')[0].strip()
            if item:
                imported.add(item)
    for m in import_default_pattern.finditer(content):
        name = m.group(1)
        if name not in ('type', 'React'):
            imported.add(name)

# Also check for usage in JSX or references
all_content = ''
for fp in all_files:
    with open(fp, 'r', encoding='utf-8') as fh:
        all_content += fh.read() + '\n'

# Find exports never imported by another file
dead = []
for name, files in sorted(exports.items()):
    if name in imported:
        continue
    # Skip if it's only in test files
    non_test_files = [f for f in files if '.test.' not in f]
    if not non_test_files:
        continue
    # Skip very common/framework names
    if name in ('App', 'main', 'default'):
        continue
    # Check if name appears in content beyond its own export
    # count occurrences - if only in the exporting file(s), it's dead
    count = len(re.findall(r'\b' + re.escape(name) + r'\b', all_content))
    export_count = len(files)
    if count <= export_count + 1:  # +1 for some slack
        dead.append((name, non_test_files))

if dead:
    print(f'POTENTIALLY DEAD EXPORTS ({len(dead)}):')
    for name, files in dead:
        print(f'  {name} in {", ".join(files)}')
else:
    print('No dead exports found.')

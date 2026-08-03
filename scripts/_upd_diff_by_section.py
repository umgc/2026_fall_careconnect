import difflib
import re

def load(path):
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    tags = []
    texts = []
    for l in lines:
        if '\t' in l:
            tag, text = l.split('\t', 1)
        else:
            tag, text = 'Body', l
        tags.append(tag)
        texts.append(text)
    return tags, texts

t_tags, t_texts = load(r'C:\Users\ravic\Downloads\_upd_target_tagged.txt')
e_tags, e_texts = load(r'C:\Users\ravic\Downloads\_upd_edit_tagged.txt')


def norm(text):
    text = re.sub(r'^\u25cf\s*', '', text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text


t_norm = [norm(x) for x in t_texts]
e_norm = [norm(x) for x in e_texts]

sm = difflib.SequenceMatcher(None, t_norm, e_norm, autojunk=False)
ops = sm.get_opcodes()


def current_heading(tags, texts, idx):
    for i in range(idx, -1, -1):
        if tags[i] in ('Heading1', 'Heading2', 'Heading3', 'Heading4') and texts[i].strip():
            return f'{tags[i]}: {texts[i].strip()}'
    return '(front matter)'


out = []
for tag, i1, i2, j1, j2 in ops:
    if tag == 'equal':
        continue
    t_block = [(e_tags[j] if False else t_tags[i], t_texts[i]) for i in range(i1, i2) if t_texts[i].strip()]
    e_block = [(e_tags[j], e_texts[j]) for j in range(j1, j2) if e_texts[j].strip()]
    if not t_block and not e_block:
        continue
    heading_ctx = current_heading(e_tags, e_texts, j1) if e_block else current_heading(t_tags, t_texts, i1)
    out.append({
        'tag': tag,
        'heading': heading_ctx,
        't_block': t_block,
        'e_block': e_block,
    })

with open(r'c:\Users\ravic\2026_summer_careconnect\scripts\_upd_diff_output.txt', 'w', encoding='utf-8') as f:
    f.write(f'Total blocks: {len(out)}\n\n')
    for idx, o in enumerate(out):
        f.write(f'=== Block {idx} [{o["tag"]}] under {o["heading"]} ===\n')
        for style, text in o['t_block']:
            f.write(f'  T ({style}): {text}\n')
        for style, text in o['e_block']:
            f.write(f'  E ({style}): {text}\n')
        f.write('\n')

print('wrote', len(out), 'blocks')

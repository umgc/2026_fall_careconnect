import sys
import zipfile
from xml.etree import ElementTree as ET

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def extract_with_headings(path, out_path):
    with zipfile.ZipFile(path) as z:
        xml = z.read('word/document.xml')
    root = ET.fromstring(xml)
    body = root.find(W + 'body')
    lines = []
    for p in body.iter(W + 'p'):
        pPr = p.find(W + 'pPr')
        style = None
        if pPr is not None:
            pStyle = pPr.find(W + 'pStyle')
            if pStyle is not None:
                style = pStyle.get(W + 'val')
        texts = ''.join(t.text or '' for t in p.iter(W + 't'))
        tag = style if style else 'Body'
        lines.append(f'{tag}\t{texts}')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'{path}: {len(lines)} paragraphs -> {out_path}')


if __name__ == '__main__':
    extract_with_headings(sys.argv[1], sys.argv[2])

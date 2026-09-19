#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
World Space · 中文衬线子集构建（单文件零构建站唯一的离线一次性工具）

页面里的 "MingOS Serif" 是 Noto Serif SC（SIL OFL 1.1，全文见 web/FONT-LICENSE.txt）
的按需子集：只包含 web/index.html <body> 里真正出现的非 ASCII 字符。
子集结果以 base64 内联回 index.html 的
    /* MING-FONT:BEGIN */ … /* MING-FONT:END */
之间——页面本身仍然是零外部请求、零构建产物。

用法：
    pip install fonttools brotli          # 只需一次
    python web/build-font.py              # 联网拉 Google Fonts 分片 → 子集 → 内联
    python web/build-font.py --check      # 只审计缺字，不写文件
    python web/build-font.py --fallback   # 网络不可用时：抽出 Family-Space 页内已内联的
                                          # 子集作为起点（覆盖不等于本页文案，会打印审计）

移植自 MingOS-web/tools/build-font.py（下载 + 分片子集 + merge + 规整 name 表），
逻辑不改，只把输入换成单文件 HTML、并加上「内联回写 + 缺字审计」两步。
"""
import os, re, sys, base64, shutil, subprocess, tempfile, html as htmllib, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(HERE, 'index.html')
FALLBACK_SRC = os.path.abspath(os.path.join(HERE, '..', '..',
                            'Family-Space', 'website', 'index.html'))
BEGIN, END = '/* MING-FONT:BEGIN */', '/* MING-FONT:END */'

UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
CSS_URL = 'https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@400&display=swap'

FACE_TMPL = ('/* MING-FONT:BEGIN */\n'
             '@font-face{{\n'
             '  font-family:"MingOS Serif";\n'
             '  font-style:normal;\n'
             '  font-weight:400;\n'
             '  font-display:swap;\n'
             '  src:url(data:font/woff2;base64,{b64}) format("woff2");\n'
             '}}\n'
             '/* MING-FONT:END */')


def get(url, binary=False, tries=4):
    """curl 优先（部分环境 Python urllib 与 Google TLS 握手会失败），失败退回 urllib。"""
    last = None
    for n in range(tries):
        try:
            if shutil.which('curl'):
                p = subprocess.run(['curl', '-s', '-m', '150', '-L', '-A', UA, url],
                                   capture_output=True, timeout=200)
                if p.returncode == 0 and p.stdout:
                    return p.stdout if binary else p.stdout.decode('utf-8')
                last = 'curl rc=%s' % p.returncode
            else:
                req = urllib.request.Request(url, headers={'User-Agent': UA})
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                return data if binary else data.decode('utf-8')
        except Exception as e:
            last = str(e)[:80]
        import time
        time.sleep(2 * (n + 1))
    raise RuntimeError('下载失败 %s（%s）' % (url[:70], last))


def page_chars():
    """<body> 里的可见文本，非 ASCII 字符集合（与 MingOS 版同规则）。"""
    html = open(HTML, encoding='utf-8').read()
    body = html.split('<body', 1)[1]
    body = re.sub(r'<script[\s\S]*?</script>', '', body)
    body = re.sub(r'<style[\s\S]*?</style>', '', body)
    txt = re.sub(r'<[^>]+>', '', body)
    txt = htmllib.unescape(txt)
    return sorted({c for c in txt if ord(c) > 127})


def parse_range(ur):
    cps = set()
    for p in ur.split(','):
        p = p.strip().replace('U+', '').replace('u+', '')
        if '-' in p:
            a, b = p.split('-')
            cps.update(range(int(a, 16), int(b, 16) + 1))
        elif p:
            cps.add(int(p, 16))
    return cps


def build_subset(chars):
    """Google Fonts 分片 → 按 unicode-range 取需要的片 → 逐片子集 → merge → 再整体子集。"""
    need = {ord(c) for c in chars}
    css = get(CSS_URL)
    slices = []
    for b in re.findall(r'@font-face\s*\{(.*?)\}', css, re.S):
        u = re.search(r'src:\s*url\((.*?)\)', b)
        r = re.search(r'unicode-range:\s*(.*?);', b)
        if u and r:
            slices.append((u.group(1), r.group(1).strip()))
    picked = [i for i, (_, r) in enumerate(slices) if parse_range(r) & need]
    print('共 %d 个分片，需要其中 %d 个' % (len(slices), len(picked)))

    tmp = tempfile.mkdtemp(prefix='ws-font-')
    try:
        parts, covered = [], set()
        for i in picked:
            url = slices[i][0]
            raw = os.path.join(tmp, 'raw%d.woff2' % i)
            open(raw, 'wb').write(get(url, binary=True))
            mine = sorted(parse_range(slices[i][1]) & need)
            covered.update(mine)
            txtf = os.path.join(tmp, 't%d.txt' % i)
            open(txtf, 'w', encoding='utf-8').write(''.join(chr(c) for c in mine))
            dst = os.path.join(tmp, 's%03d.woff2' % i)
            subprocess.run([sys.executable, '-m', 'fontTools.subset', raw,
                            '--text-file=' + txtf, '--flavor=woff2', '--output-file=' + dst,
                            '--layout-features=', '--no-hinting', '--desubroutinize',
                            '--drop-tables+=DSIG,BASE,GDEF,GPOS,GSUB', '--name-IDs=1,2,3,4,6',
                            '--notdef-outline'], check=True, capture_output=True)
            parts.append(dst)
            print('  分片 %-3d %d 字 → %d B' % (i, len(mine), os.path.getsize(dst)))

        miss_source = sorted(need - covered)
        if miss_source:
            print('  注意：以下字符不在 Noto Serif SC 的取样分片里：')
            print('   ', ' '.join('U+%04X(%s)' % (m, chr(m)) for m in miss_source))

        merged = os.path.join(tmp, 'merged.ttf')
        subprocess.run([sys.executable, '-m', 'fontTools.merge'] + parts +
                       ['--output-file=' + merged], check=True, capture_output=True)

        final = os.path.join(tmp, 'final.woff2')
        allchars = os.path.join(tmp, 'all.txt')
        open(allchars, 'w', encoding='utf-8').write(''.join(chars))
        subprocess.run([sys.executable, '-m', 'fontTools.subset', merged,
                        '--text-file=' + allchars, '--flavor=woff2', '--output-file=' + final,
                        '--layout-features=', '--no-hinting', '--desubroutinize',
                        '--name-IDs=1,2,3,4,6', '--notdef-outline'], check=True, capture_output=True)

        # 规整 name 表与字重（保留名 "MingOS Serif" 不改）
        from fontTools.ttLib import TTFont
        f = TTFont(final)
        n = f['name']
        n.names = [r for r in n.names if r.platformID != 1]
        for nid, val in [(1, 'MingOS Serif'), (2, 'Regular'), (3, 'MingOSSerif-Regular'),
                         (4, 'MingOS Serif'), (6, 'MingOSSerif-Regular')]:
            n.setName(val, nid, 3, 1, 0x409)
            n.setName(val, nid, 1, 0, 0)
        f['OS/2'].usWeightClass = 400
        f.flavor = 'woff2'
        out = os.path.join(tmp, 'out.woff2')
        f.save(out)
        data = open(out, 'rb').read()
        font = TTFont(out)
        print('最终字体: %d B  字形 %d' % (len(data), font['maxp'].numGlyphs))
        return data, font
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def fallback_font():
    """网络不可用时：抽 Family-Space 页内已内联的那份子集作为起点（覆盖 ≠ 本页文案）。"""
    if not os.path.exists(FALLBACK_SRC):
        raise RuntimeError('找不到兜底源 %s' % FALLBACK_SRC)
    src = open(FALLBACK_SRC, encoding='utf-8').read()
    m = re.search(r'@font-face\s*\{[\s\S]*?url\(data:font/woff2;base64,([A-Za-z0-9+/=]+)\)', src)
    if not m:
        raise RuntimeError('Family-Space 页面里没找到内联的 woff2 base64')
    print('兜底：复用 Family-Space/website/index.html 内联子集（该子集不是按本页文案切的）')
    return base64.b64decode(m.group(1))


def audit(data, chars):
    """真正的缺字审计：看最终字体 cmap 里有没有这个码位。"""
    from fontTools.ttLib import TTFont
    import io
    cmap = TTFont(io.BytesIO(data)).getBestCmap()
    missing = [c for c in chars if ord(c) not in cmap]
    print('页面非 ASCII 字符 %d 个，字体覆盖 %d 个' % (len(chars), len(chars) - len(missing)))
    if missing:
        print('MISSING GLYPHS (%d)：以下字符会静默回退到系统宋体栈：' % len(missing))
        print('  ' + ' '.join('U+%04X(%s)' % (ord(c), c) for c in missing))
    else:
        print('MISSING GLYPHS (0)：无缺字')
    return missing


def inline(data):
    html = open(HTML, encoding='utf-8').read()
    if BEGIN not in html or END not in html:
        raise RuntimeError('页面里找不到 MING-FONT:BEGIN/END 标记')
    block = FACE_TMPL.format(b64=base64.b64encode(data).decode('ascii'))
    out = re.sub(re.escape(BEGIN) + r'[\s\S]*?' + re.escape(END), lambda _: block, html, count=1)
    tmp = HTML + '.tmp'
    open(tmp, 'w', encoding='utf-8', newline='\n').write(out)
    os.replace(tmp, HTML)
    print('已内联回 %s（+%d B base64）' % (os.path.relpath(HTML, HERE).replace('\\', '/'),
                                          len(block)))


def main():
    check = '--check' in sys.argv
    chars = page_chars()
    print('页面需要 %d 个非 ASCII 字符' % len(chars))
    if not chars:
        print('没有需要衬线化的字符。'); return 0

    if '--fallback' in sys.argv:
        data = fallback_font()
    else:
        data, _ = build_subset(chars)

    audit(data, chars)
    if check:
        print('--check：不写文件'); return 0
    inline(data)
    return 0


if __name__ == '__main__':
    sys.exit(main())

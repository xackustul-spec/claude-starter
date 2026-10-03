// Назначение: замер вёрстки открытой страницы — находит наезды, вылезания и обрезанный текст числами, а не на глаз.
// Запуск: выполнить этот файл целиком в странице (javascript_tool встроенного браузера, evaluate в Playwright
// или chrome-devtools) на каждой ширине окна. Возвращает строку JSON: {width, problems, items:[{kind, a, b, by}]}.
// Ничего не меняет на странице. Намеренное наложение помечается в разметке атрибутом data-overlap-ok.
(() => {
  const doc = document.documentElement, vw = doc.clientWidth, TOL = 2, items = [];
  const cs = el => getComputedStyle(el);
  const rect = el => el.getBoundingClientRect();
  const shown = el => { const s = cs(el), r = rect(el);
    return s.display !== 'none' && s.visibility !== 'hidden' && parseFloat(s.opacity) > 0.01 && r.width > 1 && r.height > 1; };
  const okFlag = el => !!el.closest('[data-overlap-ok]');
  const name = el => { let n = el.tagName.toLowerCase(); if (el.id) n += '#' + el.id;
    const c = (el.getAttribute('class') || '').trim().split(/\s+/).filter(Boolean).slice(0, 2).join('.'); if (c) n += '.' + c;
    const t = (el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 30); return t ? n + ' «' + t + '»' : n; };
  const cut = (a, b) => { const w = Math.min(a.right, b.right) - Math.max(a.left, b.left), h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
    return (w > TOL && h > TOL) ? [Math.round(w), Math.round(h)] : null; };
  const add = (kind, a, b, by) => { if (items.length < 40) items.push({ kind, a, b: b || '', by: by || '' }); };
  const scroller = el => { for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
    const s = cs(p); if (/(auto|scroll)/.test(s.overflowX + s.overflowY)) return true; } return false; };
  const clipped = el => { for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
    const s = cs(p); if (/(hidden|clip|auto|scroll)/.test(s.overflowX + s.overflowY)) return true; } return false; };

  // 1. Страница шире окна — появляется горизонтальная прокрутка.
  if (doc.scrollWidth > vw + 1) add('страница шире окна', 'html', '', (doc.scrollWidth - vw) + 'px');

  const all = [...document.body.querySelectorAll('*')].filter(el => !/^(script|style|svg|path|g|defs|br|option)$/i.test(el.tagName) && !el.closest('svg') && shown(el));
  for (const el of all) {
    if (okFlag(el)) continue;
    const r = rect(el), s = cs(el);
    // 2. Элемент торчит за правый или левый край окна (и не лежит в прокручиваемом блоке).
    if ((r.right > vw + TOL || r.left < -TOL) && s.position !== 'fixed' && !scroller(el) && !clipped(el))
      add('вылезает за край окна', name(el), '', Math.round(Math.max(r.right - vw, -r.left)) + 'px');
    // 3. Ребёнок вылезает из родителя, у которого содержимое не обрезается.
    const p = el.parentElement;
    if (p && p !== document.body && shown(p) && !/(absolute|fixed)/.test(s.position) && s.float === 'none') {
      const pr = rect(p), ps = cs(p);
      if (/visible/.test(ps.overflowX) && (r.right > pr.right + TOL || r.left < pr.left - TOL) && pr.width > 4)
        add('вылезает из своего блока', name(el), name(p), Math.round(Math.max(r.right - pr.right, pr.left - r.left)) + 'px');
    }
    // 4. Текст не помещается: обрезан без многоточия или выливается наружу.
    const ownText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (ownText && el.scrollWidth > el.clientWidth + TOL && el.clientWidth > 0 && s.display !== 'inline') {
      if (/hidden|clip/.test(s.overflowX) && s.textOverflow !== 'ellipsis') add('текст обрезан без многоточия', name(el), '', (el.scrollWidth - el.clientWidth) + 'px');
      else if (/visible/.test(s.overflowX)) add('текст выливается из блока', name(el), '', (el.scrollWidth - el.clientWidth) + 'px');
    }
    if (ownText && el.scrollHeight > el.clientHeight + TOL && /hidden|clip/.test(s.overflowY) && el.clientHeight > 0 && !s.webkitLineClamp.match(/\d/))
      add('текст обрезан по высоте', name(el), '', (el.scrollHeight - el.clientHeight) + 'px');
  }
  // 5. Соседи в обычном потоке наезжают друг на друга.
  const parents = new Set(all.map(el => el.parentElement).filter(Boolean));
  for (const p of parents) {
    if (okFlag(p)) continue;
    const kids = [...p.children].filter(k => all.includes(k) && !/(absolute|fixed|sticky)/.test(cs(k).position) && !k.hasAttribute('data-overlap-ok'));
    for (let i = 0; i < kids.length; i++) for (let j = i + 1; j < kids.length; j++) {
      const c = cut(rect(kids[i]), rect(kids[j])); if (c) add('соседние блоки наезжают', name(kids[i]), name(kids[j]), c[0] + '×' + c[1] + 'px');
    }
  }
  // 6. Надпись наезжает на надпись (в том числе выпавшие и приклеенные элементы).
  const texts = all.filter(el => !okFlag(el) && [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())).slice(0, 900);
  const boxes = texts.map(el => { const rg = document.createRange(); rg.selectNodeContents(el); return [el, rg.getBoundingClientRect()]; });
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const [a, ra] = boxes[i], [b, rb] = boxes[j];
    if (a.contains(b) || b.contains(a)) continue;
    const c = cut(ra, rb); if (c && c[0] > 3 && c[1] > 3) add('надписи наезжают', name(a), name(b), c[0] + '×' + c[1] + 'px');
  }
  // 7. Выпавший элемент (значок, бейдж, кнопка с position:absolute) закрывает надпись.
  const floats = all.filter(el => /absolute/.test(cs(el).position) && !okFlag(el) && !texts.includes(el) && rect(el).width < vw * 0.5).slice(0, 300);
  for (const f of floats) for (const [b, rb] of boxes) {
    if (f.contains(b) || b.contains(f) || !f.parentElement.contains(b)) continue;
    const c = cut(rect(f), rb); if (c && c[0] > 3 && c[1] > 3) add('значок или бейдж закрывает надпись', name(f), name(b), c[0] + '×' + c[1] + 'px');
  }
  return JSON.stringify({ width: vw, problems: items.length, items });
})()

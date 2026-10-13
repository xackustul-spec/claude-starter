// Назначение: проверка положения блока числами — «куда переместить» в словах владельца → утверждения о координатах.
// Запуск: в странице сначала задать window.KIT_PLACE = [[что, отношение, относительно чего, число?], ...], затем
// выполнить этот файл целиком (javascript_tool / evaluate). Возвращает JSON: {ok, lines:[«✓/✗ утверждение: числа»]}.
// Отношения: «внутри» (целиком в границах), «ниже» / «выше» (по вертикали, без наезда), «левее» / «правее»,
// «на уровне» (верх или середина совпадают до 4 px), «ширина%» (ширина — N% от второго, допуск 1%),
// «не выходит вниз» (низ не ниже низа второго). Ничего не меняет на странице.
(() => {
  const T = 2, spec = window.KIT_PLACE || [], lines = [];
  const R = s => { const el = document.querySelector(s); return el ? el.getBoundingClientRect() : null; };
  const n = v => Math.round(v);
  let ok = true;
  for (const [a, rel, b, num] of spec) {
    const x = R(a), y = R(b);
    if (!x || !y) { ok = false; lines.push('✗ ' + a + ' ' + rel + ' ' + b + ': не найден ' + (!x ? a : b)); continue; }
    let pass = false, info = '';
    switch (rel) {
      case 'внутри': pass = x.left >= y.left - T && x.right <= y.right + T && x.top >= y.top - T && x.bottom <= y.bottom + T;
        info = `${a} [${n(x.left)},${n(x.top)}–${n(x.right)},${n(x.bottom)}] в ${b} [${n(y.left)},${n(y.top)}–${n(y.right)},${n(y.bottom)}]`; break;
      case 'ниже': pass = x.top >= y.bottom - T; info = `верх ${a} ${n(x.top)} ≥ низ ${b} ${n(y.bottom)}`; break;
      case 'выше': pass = x.bottom <= y.top + T; info = `низ ${a} ${n(x.bottom)} ≤ верх ${b} ${n(y.top)}`; break;
      case 'левее': pass = x.right <= y.left + T; info = `правый край ${a} ${n(x.right)} ≤ левый ${b} ${n(y.left)}`; break;
      case 'правее': pass = x.left >= y.right - T; info = `левый край ${a} ${n(x.left)} ≥ правый ${b} ${n(y.right)}`; break;
      case 'на уровне': { const dt = Math.abs(x.top - y.top), dm = Math.abs((x.top + x.bottom) / 2 - (y.top + y.bottom) / 2);
        pass = dt <= 4 || dm <= 4; info = `верх ${n(x.top)}/${n(y.top)}, середина ${n((x.top + x.bottom) / 2)}/${n((y.top + y.bottom) / 2)}`; break; }
      case 'ширина%': { const p = x.width / y.width * 100; pass = Math.abs(p - Number(num)) <= 1; info = `${p.toFixed(1)}% от ${b}, нужно ${num}%`; break; }
      case 'не выходит вниз': pass = x.bottom <= y.bottom + T; info = `низ ${a} ${n(x.bottom)} ≤ низ ${b} ${n(y.bottom)}`; break;
      default: info = 'неизвестное отношение «' + rel + '»';
    }
    if (!pass) ok = false;
    lines.push((pass ? '✓ ' : '✗ ') + a + ' ' + rel + ' ' + b + (num !== undefined ? ' ' + num : '') + ': ' + info);
  }
  return JSON.stringify({ width: document.documentElement.clientWidth, ok, lines });
})()

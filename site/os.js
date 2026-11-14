(function () {
  var u = navigator.userAgent, os;
  if (/Android/i.test(u)) os = 'android';
  // iPadOS asks for the desktop site, so it looks like a Mac with a touch screen
  else if (/iPhone|iPad|iPod/.test(u) || (/Macintosh/.test(u) && navigator.maxTouchPoints > 1)) os = 'iphone';
  else if (/Macintosh/.test(u)) os = 'macos';
  else if (/Windows/.test(u)) os = 'windows';
  else if (/Linux x86_64/.test(u) && !/CrOS/.test(u)) os = 'linux';
  var row = os && document.getElementById('dl-' + os), btn = document.getElementById('get');
  if (!row || !btn) return;
  row.classList.add('you');
  btn.querySelector('span').textContent = btn.dataset[os];
  // an unsigned ipa won't install from safari, so iPhone goes to its row for the home screen steps
  btn.href = os === 'iphone' ? '#dl-iphone' : row.querySelector('.get').href;
})();

// the try-it box in the hero: "lunch 450" becomes a row. A demo only, nothing is kept.
(function () {
  var f = document.getElementById('try');
  if (!f) return;
  var input = f.querySelector('input'), list = document.getElementById('try-list'),
    sum = document.getElementById('try-sum'), hint = f.querySelector('.try-hint'),
    cats = JSON.parse(f.dataset.cats), income = f.dataset.income.split(' '), total = 0;
  function money(n) {
    return (n < 0 ? '−' : '+') + Math.abs(n).toLocaleString(undefined, { maximumFractionDigits: 2 });
  }
  function show() { sum.textContent = total ? money(total) : '0'; }
  function add(text) {
    // nepali digits count too
    text = text.replace(/[०-९]/g, function (d) { return d.charCodeAt(0) - 0x0966; });
    var m = text.match(/\d[\d,]*(\.\d+)?/), amount = m ? parseFloat(m[0].replace(/,/g, '')) : 0;
    hint.hidden = amount > 0;
    if (!(amount > 0)) return;
    var name = text.replace(m[0], ' ').replace(/\s+/g, ' ').trim() || f.dataset.blank;
    var words = name.toLowerCase().split(' '), cat = '';
    var isIn = words.some(function (w) { return income.indexOf(w) >= 0; });
    for (var c in cats) if (words.some(function (w) { return cats[c].split(' ').indexOf(w) >= 0; })) cat = c;
    var li = document.createElement('li'), left = document.createElement('span'),
      b = document.createElement('b'), i = document.createElement('i');
    b.textContent = name.charAt(0).toUpperCase() + name.slice(1);
    left.appendChild(b);
    if (cat) { var s = document.createElement('small'); s.textContent = cat; left.appendChild(s); }
    i.textContent = money(isIn ? amount : -amount);
    li.className = isIn ? 'in new' : 'new';
    li.appendChild(left); li.appendChild(i);
    list.insertBefore(li, list.firstChild);
    while (list.children.length > 5) list.removeChild(list.lastChild);
    total += isIn ? amount : -amount;
    show();
    input.value = '';
  }
  [].forEach.call(list.children, function (li) { total += parseFloat(li.dataset.v) || 0; });
  show();
  f.addEventListener('submit', function (e) { e.preventDefault(); add(input.value); });
  [].forEach.call(f.querySelectorAll('.try-eg button'), function (b) {
    b.addEventListener('click', function () { add(b.textContent); });
  });
})();

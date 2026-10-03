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

/* AI 从零开始 · 共用脚本（零外部请求；只做三件事：复制、记录“做成了”、展开/收起） */
(function () {
  'use strict';

  function markCopied(btn, ok) {
    var original = btn.getAttribute('data-label') || btn.textContent;
    btn.setAttribute('data-label', original);
    btn.textContent = ok ? '已复制 ✓' : '没复制成功，请长按上面那段字手动复制';
    btn.setAttribute('data-ok', ok ? '1' : '0');
    window.setTimeout(function () {
      btn.textContent = original;
      btn.removeAttribute('data-ok');
    }, ok ? 2200 : 6000);
  }

  function legacyCopy(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.top = '-1000px';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, text.length);
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  document.addEventListener('click', function (ev) {
    var btn = ev.target.closest('button.copy');
    if (!btn) return;
    var box = btn.closest('.saybox');
    var src = box && box.querySelector('.saytxt');
    if (!src) return;
    var text = src.textContent.replace(/^\s+|\s+$/g, '');
    var done = function (ok) { markCopied(btn, ok); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(legacyCopy(text)); });
    } else {
      done(legacyCopy(text));
    }
  });

  document.addEventListener('input', function (ev) {
    var box = ev.target;
    if (!box || box.type !== 'checkbox' || !box.id) return;
    try { window.localStorage.setItem('ws_ai_' + box.id, box.checked ? '1' : '0'); } catch (e) { /* 隐私模式：不记录，也不报错 */ }
  });

  document.addEventListener('DOMContentLoaded', function () {
    var boxes = document.querySelectorAll('input[type="checkbox"][id]');
    for (var i = 0; i < boxes.length; i++) {
      try {
        if (window.localStorage.getItem('ws_ai_' + boxes[i].id) === '1') boxes[i].checked = true;
      } catch (e) { /* 忽略 */ }
    }
  });
})();

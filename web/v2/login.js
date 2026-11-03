/* 登录页只有一件事：把账号密码交给 /api/auth/login，成功就进产品页。
 * 错误只说"账号或密码不正确"，不区分账号不存在和密码错；配置坏了如实说服务不可用。 */
const $ = id => document.getElementById(id);
const form = $('f'), msg = $('msg'), btn = $('go');

function show(text) { msg.textContent = text; msg.hidden = false; }
function note(text) { msg.className = 'notice msg-note'; show(text); }

(async () => {
  const params = new URLSearchParams(location.search);
  if (params.get('expired') === '1') note('登录已过期，请重新进入。');
  try {
    const me = await fetch('/api/auth/me');
    if (me.ok) return location.replace('/');
    if (me.status === 503) return note('服务没有配置好，暂时无法进入。请联系维护者。');
  } catch (e) { /* 网络问题留给提交时的错误处理 */ }
})();

form.onsubmit = async e => {
  e.preventDefault();
  msg.hidden = true; msg.className = 'err';
  btn.disabled = true;
  try {
    const res = await fetch('/api/auth/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ username: $('username').value, password: $('password').value }),
    });
    const j = await res.json().catch(() => ({}));
    if (res.status === 200 && j.ok) {
      location.replace('/');
      return;
    }
    if (res.status === 429) show(j.message || '尝试次数太多，请等几分钟再试。');
    else if (res.status === 503) show(j.message || '服务没有配置好，暂时无法登录。');
    else if (res.status === 400) show('请填写账号和密码。');
    else show('账号或密码不正确。');
  } catch (x) {
    show('连不上服务。检查网络后再试一次。');
  }
  btn.disabled = false;
};

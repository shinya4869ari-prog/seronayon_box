// Minimal client: uses local server via LOCAL_API_URL and LOCAL_API_TOKEN stored in localStorage
const analyzeBtn = document.getElementById('analyzeBtn');
const textEl = document.getElementById('text');
const resultEl = document.getElementById('result');

const LOCAL_API_URL = localStorage.getItem('LOCAL_API_URL') || 'http://100.x.x.x:8000';
const apiToken = localStorage.getItem('LOCAL_API_TOKEN') || '';

function detectLangHint(text){
  if (/[ㄱ-ㅎㅏ-ㅣ가-힣]/.test(text)) return 'ko';
  if (/[A-Za-z]/.test(text)) return 'en';
  return 'ja';
}

analyzeBtn.onclick = async () => {
  const text = textEl.value.trim();
  if (!text) { alert('スニペットを入力してください'); return; }
  resultEl.innerHTML = '解析中…';
  const hint = detectLangHint(text);
  const tokens = text.split(/[ \t\n\r,。.、\.\!?·•/]+/).filter(Boolean);
  // parallel lookups
  const results = await Promise.all(tokens.map(async t => {
    try {
      const url = `${LOCAL_API_URL}/lookup?word=${encodeURIComponent(t)}`;
      const res = await fetch(url, { headers: { 'x-api-key': apiToken }});
      if (!res.ok) return { text: t, ok:false };
      const data = await res.json();
      return { text: t, ok:true, data };
    } catch (e) { return { text:t, ok:false }; }
  }));
  // render
  let html = `<div><strong>言語推定:</strong> ${hint}</div><div>`;
  results.forEach(r => {
    html += `<div style="margin-top:8px"><strong>${r.text}</strong> — `;
    if (r.ok) {
      const tr = r.data.translation_ja || r.data.translation;
      html += `<span>${Array.isArray(tr) ? tr.join(', ') : tr}</span>`;
    } else html += `<em>辞書なし</em>`;
    html += `</div>`;
  });
  html += `</div>`;
  resultEl.innerHTML = html;
};

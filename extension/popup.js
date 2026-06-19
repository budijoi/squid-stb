/* Squid Cache Monitor — popup.js */

const C = {
  ls: (k, v) => { if (v !== undefined) { localStorage.setItem(k, v); return } return localStorage.getItem(k) },
  $: (s, p) => (p || document).querySelector(s),
  $$: (s, p) => (p || document).querySelectorAll(s)
};

const serverInput = C.$('#serverInput');
const connectBtn = C.$('#connectBtn');
const statusTitle = C.$('#statusTitle');
const loadingView = C.$('#loadingView');
const errorView = C.$('#errorView');
const errorMsg = C.$('#errorMsg');
const retryBtn = C.$('#retryBtn');
const mainView = C.$('#mainView');
const ringPct = C.$('#ringPct');
const hitRing = C.$('#hitRing');
const totalReq = C.$('#totalReq');
const cacheSize = C.$('#cacheSize');
const uptime = C.$('#uptime');
const domainCount = C.$('#domainCount');
const hitsNum = C.$('#hitsNum');
const missesNum = C.$('#missesNum');
const tunnelsNum = C.$('#tunnelsNum');
const recentList = C.$('#recentList');
const domainList = C.$('#domainList');
const lastUpdate = C.$('#lastUpdate');

let server = C.ls('server') || '192.168.101.22:8080';
let pollTimer = null;

serverInput.value = server;

function showView(view) {
  [loadingView, errorView, mainView].forEach(v => v.style.display = 'none');
  if (view) view.style.display = '';
}

function updateStatus(ok) {
  statusTitle.className = ok ? 'on' : 'off';
}

function badgeClass(result) {
  if (result.includes('HIT')) return 'hit';
  if (result === 'TCP_MISS') return 'miss';
  if (result === 'TCP_TUNNEL') return 'tunnel';
  if (result === 'TCP_DENIED') return 'denied';
  return 'other';
}

async function fetchAPI(endpoint) {
  const resp = await fetch(`http://${server}${endpoint}`, { signal: AbortSignal.timeout(5000) });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

async function loadData() {
  try {
    const [stats, recentData, domainsData] = await Promise.all([
      fetchAPI('/api/stats'),
      fetchAPI('/api/recent'),
      fetchAPI('/api/domains')
    ]);

    showView(mainView);
    updateStatus(true);

    // Hit ratio ring
    const pct = stats.hit_ratio || 0;
    ringPct.textContent = Math.round(pct);
    const circ = 2 * Math.PI * 42;  // r=42
    hitRing.style.strokeDasharray = circ;
    hitRing.style.strokeDashoffset = circ - (circ * pct / 100);

    // Metrics
    totalReq.textContent = stats.total_requests.toLocaleString();
    cacheSize.textContent = stats.cache_size_mb + ' MB';
    uptime.textContent = stats.uptime || '-';
    domainCount.textContent = (domainsData || []).length;

    // Stat boxes
    hitsNum.textContent = stats.cache_hits.toLocaleString();
    missesNum.textContent = stats.cache_misses.toLocaleString();
    tunnelsNum.textContent = stats.cache_tunnels.toLocaleString();

    // Recent requests
    recentList.innerHTML = '';
    (recentData || []).forEach(r => {
      const div = document.createElement('div');
      div.className = 'item';
      div.innerHTML = `
        <span class="badge ${badgeClass(r.result)}">${r.result}</span>
        <span class="url">${r.url} <small>${r.method}</small></span>
        <span class="ms">${r.ms}ms</span>
      `;
      recentList.appendChild(div);
    });

    // Top domains
    domainList.innerHTML = '';
    const maxTotal = (domainsData && domainsData[0]) ? domainsData[0].total : 1;
    (domainsData || []).forEach(d => {
      const pctW = Math.min(100, Math.round((d.hits / d.total) * 100));
      const div = document.createElement('div');
      div.className = 'domain-item';
      div.innerHTML = `
        <span class="name">${d.domain}</span>
        <span class="cnt">${d.total}</span>
        <div class="bar-wrap"><div class="bar-fill" style="width:${Math.round((d.total/maxTotal)*100)}%"></div></div>
      `;
      domainList.appendChild(div);
    });

    lastUpdate.textContent = new Date().toLocaleTimeString();

  } catch (e) {
    showView(errorView);
    updateStatus(false);
    errorMsg.textContent = e.name === 'TimeoutError'
      ? 'Timeout — server tidak merespon'
      : `Tidak dapat terhubung ke ${server}`;
  }
}

function startPoll() {
  if (pollTimer) clearInterval(pollTimer);
  showView(loadingView);
  loadData();
  pollTimer = setInterval(loadData, 3000);
}

function connect() {
  server = serverInput.value.trim() || '192.168.101.22:8080';
  C.ls('server', server);
  startPoll();
}

connectBtn.addEventListener('click', connect);
retryBtn.addEventListener('click', startPoll);
serverInput.addEventListener('keydown', e => { if (e.key === 'Enter') connect(); });

// Start
startPoll();

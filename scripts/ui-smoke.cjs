const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
let chromium;
try {
  ({ chromium } = require('playwright-core'));
} catch (_) {
  throw new Error('UI_SMOKE_PREREQUISITE_ERROR=Missing playwright-core. Run "npm ci" in the project root before the browser smoke test.');
}

const root = path.resolve(__dirname, '..');
const outputDir = path.join(root, 'output', 'playwright');
const browserProfile = path.join(outputDir, '.chrome-profile');
const chromeCandidates = [
  process.env.PALWORLD_UI_SMOKE_CHROME,
  process.env.CHROME_PATH,
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Google', 'Chrome', 'Application', 'chrome.exe'),
].filter(Boolean);
const chromePath = chromeCandidates.find(candidate => fs.existsSync(candidate));
const devToolsPortFile = path.join(browserProfile, 'DevToolsActivePort');
const panelPortPath = path.join(root, '.settings-panel.port');
const panelPort = fs.existsSync(panelPortPath)
  ? Number(fs.readFileSync(panelPortPath, 'utf8').trim())
  : 8213;
const panelUrl = `http://localhost:${panelPort}/`;
const allowUnhealthyEnvironment = process.env.PALWORLD_UI_SMOKE_ALLOW_UNHEALTHY === '1';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sidebarPanel(page, panel) {
  return page.locator(`.sidebar [data-panel="${panel}"]`);
}

function delay(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function cleanupProfile() {
  let lastError = null;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      await fs.promises.rm(browserProfile, {
        recursive: true,
        force: true,
        maxRetries: 10,
        retryDelay: 200,
      });
      return;
    } catch (error) {
      lastError = error;
      await delay(300 * (attempt + 1));
    }
  }
  if (lastError) console.warn(`UI_CLEANUP_WARNING=${lastError.code || lastError.message}`);
}
let chromeProcess = null;
let browserConnection = null;
let chromeLaunchError = null;

function getCdpEndpoint() {
  try {
    const portText = fs.readFileSync(devToolsPortFile, 'utf8').split(/\r?\n/, 1)[0].trim();
    const port = Number(portText);
    if (!Number.isInteger(port) || port < 1 || port > 65535) return null;
    return `http://127.0.0.1:${port}`;
  } catch (_) {
    return null;
  }
}

async function waitForCdp() {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    if (chromeLaunchError) throw new Error(`Chrome could not start: ${chromeLaunchError.message}`);
    if (chromeProcess && chromeProcess.exitCode !== null) {
      throw new Error(`Chrome exited before DevTools became ready (exit=${chromeProcess.exitCode}).`);
    }
    const endpoint = getCdpEndpoint();
    if (!endpoint) {
      await new Promise(resolve => setTimeout(resolve, 250));
      continue;
    }
    try {
      const response = await fetch(`${endpoint}/json/version`);
      const metadata = response.ok ? await response.json() : null;
      if (metadata && metadata.webSocketDebuggerUrl) return endpoint;
    } catch (_) {}
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  throw new Error('Chrome DevTools endpoint did not become ready. Set PALWORLD_UI_SMOKE_CHROME to a Chrome executable if it is not installed in a standard location.');
}

async function shutdownBrowser() {
  try {
    if (browserConnection) await browserConnection.close();
  } catch (_) {}
  if (chromeProcess && chromeProcess.exitCode === null && !chromeProcess.killed) {
    chromeProcess.kill();
    await Promise.race([
      new Promise(resolve => chromeProcess.once('exit', resolve)),
      delay(8000),
    ]);
  }
  await cleanupProfile();
}

(async () => {
  if (!chromePath) {
    throw new Error('UI_SMOKE_PREREQUISITE_ERROR=Google Chrome was not found. Set PALWORLD_UI_SMOKE_CHROME to its executable path.');
  }
  fs.mkdirSync(outputDir, { recursive: true });
  await cleanupProfile();
  chromeProcess = spawn(chromePath, [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-address=127.0.0.1',
    '--remote-debugging-port=0',
    '--remote-allow-origins=*',
    `--user-data-dir=${browserProfile}`,
    'about:blank',
  ], { stdio: 'ignore' });
  chromeProcess.once('error', error => { chromeLaunchError = error; });
  const cdpEndpoint = await waitForCdp();
  browserConnection = await chromium.connectOverCDP(cdpEndpoint);
  const context = browserConnection.contexts()[0];
  const pages = context.pages();
  const page = pages[0] || await context.newPage();
  await page.setViewportSize({ width: 1440, height: 1000 });
  page.setDefaultTimeout(15000);
  await page.addInitScript(() => localStorage.setItem('pw-lang', 'zh'));
  const browserErrors = [];
  const dashboardResponses = [];
  page.on('pageerror', error => browserErrors.push(`pageerror: ${error.message}`));
  page.on('console', message => {
    if (message.type() === 'error') browserErrors.push(`console: ${message.text()}`);
  });
  page.on('response', response => {
    if (response.url().includes('/api/dashboard')) dashboardResponses.push(response.status());
  });

  console.log('UI_STEP=browser-launched');
  await page.goto(panelUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  console.log('UI_STEP=page-loaded');
  try {
    await page.waitForFunction(() => {
      const value = document.querySelector('#dashboardFreshness')?.textContent || '';
      return value && !value.includes('正在读取');
    });
  } catch (error) {
    const freshness = await page.locator('#dashboardFreshness').innerText().catch(() => 'unavailable');
    const pageState = await page.evaluate(() => ({
      refreshState: typeof window.refreshState,
      updateStatus: document.querySelector('#updateStatus')?.textContent || '',
    })).catch(() => ({}));
    throw new Error(`Dashboard did not refresh: ${freshness}. Responses: ${dashboardResponses.join(',') || 'none'}. Page: ${JSON.stringify(pageState)}. Browser: ${browserErrors.join(' | ') || 'none'}`);
  }
  assert((await page.locator('#serverIdentityName').innerText()).includes('Palworld'), 'Server identity did not load.');
  const healthText = await page.locator('#statHealth').innerText();
  if (!healthText.includes('healthy') && !allowUnhealthyEnvironment) {
    throw new Error(`Container health was not rendered: ${healthText}. Set PALWORLD_UI_SMOKE_ALLOW_UNHEALTHY=1 only for a source/UI check without a running game runtime.`);
  }
  if (!healthText.includes('healthy')) {
    console.log(`UI_ENVIRONMENT_WARNING=health=${healthText}`);
  }
  assert(await page.locator('#serviceList .service-row').count() >= 7, 'Service status rows are incomplete.');
  let serviceStatusText = await page.locator('#serviceList').innerText();
  assert(serviceStatusText.includes('每日日志'), 'Daily log collector status is missing from the dashboard.');
  if (!allowUnhealthyEnvironment) {
    assert(serviceStatusText.includes('运行中'), 'Daily log collector is not running in the healthy-runtime smoke environment.');
  }
  const runtimeInfo = await page.evaluate(async () => {
    const response = await fetch('/api/dashboard');
    const dashboard = await response.json();
    return String(dashboard?.runtime?.runtime?.active || 'docker');
  });
  const isWindowsRuntime = runtimeInfo === 'windows';
  await page.waitForFunction(isWindows => {
    const text = document.querySelector('#updateStatus')?.textContent || '';
    return isWindows
      ? text.includes('此运行时不适用')
      : text.includes('本次启动已完成检查') || text.includes('正在更新') || text.includes('本次启动尚无记录');
  }, isWindowsRuntime);
  const updateStatusText = await page.locator('#updateStatus').innerText();
  assert(isWindowsRuntime
    ? updateStatusText.includes('此运行时不适用')
    : updateStatusText.includes('启动时自动检查'),
  `Startup update status was not rendered for ${runtimeInfo}.`);
  assert(await page.locator('#tunnelProofSteps .proof-step').count() === 5, 'Tunnel evidence chain is incomplete.');
  const cpuCapacityText = await page.locator('#statCpuCapacity').innerText();
  assert(isWindowsRuntime ? cpuCapacityText.includes('核主机') : cpuCapacityText.includes('核配额'),
    `CPU display does not identify the ${isWindowsRuntime ? 'Windows host' : 'Docker allocation'}.`);
  const cpuDisplay = await page.evaluate(() => ({
    raw: Number(document.querySelector('#statCpu')?.textContent || 0),
    capacity: document.querySelector('#statCpuCapacity')?.textContent || '',
    bar: parseFloat(document.querySelector('#statCpuBar')?.style.width || '0'),
    ring: Number((document.querySelector('#statCpuRingValue')?.textContent || '0').replace('%', '')),
    ringLabel: document.querySelector('#statCpuRing')?.getAttribute('aria-label') || '',
  }));
  const expectedCpuBar = Math.min(100, cpuDisplay.raw);
  assert(Math.abs(cpuDisplay.bar - expectedCpuBar) <= 0.2,
    `CPU allocation bar is incorrect: ${JSON.stringify({ ...cpuDisplay, expectedCpuBar })}`);
  assert(Math.abs(cpuDisplay.ring - expectedCpuBar) <= 0.2 && cpuDisplay.ringLabel.includes('%'),
    `CPU allocation ring is incorrect: ${JSON.stringify({ ...cpuDisplay, expectedCpuBar })}`);
  assert(isWindowsRuntime ? cpuDisplay.ringLabel.includes('主机进程占用') : cpuDisplay.ringLabel.includes('核配额占用'),
    `CPU ring accessibility text has the wrong runtime meaning: ${cpuDisplay.ringLabel}`);
  await page.locator('#langToggle').click();
  await page.waitForFunction(() => (document.querySelector('#langLabel')?.textContent || '').trim() === 'EN');
  const englishCpuLabel = await page.locator('#statCpuRing').getAttribute('aria-label');
  assert((isWindowsRuntime && englishCpuLabel.includes('CPU process usage')) ||
      (!isWindowsRuntime && englishCpuLabel.includes('CPU allocation usage')),
    `English CPU ring accessibility text has the wrong runtime meaning: ${englishCpuLabel}`);
  const englishRuntimeText = await page.locator('#runtimeList').innerText();
  assert(!isWindowsRuntime || englishRuntimeText.includes('Windows native'),
    `English runtime overview is not localized: ${englishRuntimeText}`);
  await page.locator('#langToggle').click();
  await page.waitForFunction(() => (document.querySelector('#langLabel')?.textContent || '').trim() === '中');
  const chineseRuntimeText = await page.locator('#runtimeList').innerText();
  assert(!isWindowsRuntime || chineseRuntimeText.includes('Windows 原生'),
    `Chinese runtime overview is not localized: ${chineseRuntimeText}`);
  await sidebarPanel(page, 'runtime').click();
  await page.waitForFunction(() => (document.querySelector('#runtimeActive')?.textContent || '').trim() !== '—');
  const activeSwitchButton = isWindowsRuntime
    ? page.locator('#btnSwitchWindows')
    : page.locator('#btnSwitchDocker');
  const alternateSwitchButton = isWindowsRuntime
    ? page.locator('#btnSwitchDocker')
    : page.locator('#btnSwitchWindows');
  assert(await activeSwitchButton.isDisabled(),
    `The active ${runtimeInfo} runtime still presents a switch action.`);
  assert(await activeSwitchButton.evaluate(element => element.classList.contains('is-current-runtime')),
    'The active runtime does not receive the non-actionable current-runtime style.');
  assert(!(await alternateSwitchButton.isDisabled()),
    `The alternate runtime target was incorrectly disabled for ${runtimeInfo}.`);
  const currentRuntimeButtonText = await activeSwitchButton.innerText();
  assert(currentRuntimeButtonText.includes('当前运行中'),
    `The active runtime button is not labeled as current: ${currentRuntimeButtonText}`);
  const runtimeSwitchHint = await page.locator('#runtimeSwitchHint').innerText();
  assert(runtimeSwitchHint.includes('当前正在运行') && runtimeSwitchHint.includes('确认'),
    `Runtime switch safety hint is incomplete: ${runtimeSwitchHint}`);
  console.log('UI_STEP=runtime-safety-asserted');
  const memoryDisplay = await page.evaluate(() => {
    const used = Number(document.querySelector('#statMem')?.textContent || 0);
    const limit = Number(document.querySelector('#statMemLimit')?.textContent || 0);
    return {
      used,
      limit,
      bar: parseFloat(document.querySelector('#statMemBar')?.style.width || '0'),
      ring: Number((document.querySelector('#statMemRingValue')?.textContent || '0').replace('%', '')),
      detail: document.querySelector('#statMemCapacity')?.textContent || '',
    };
  });
  const expectedMemoryPct = memoryDisplay.limit ? memoryDisplay.used / memoryDisplay.limit * 100 : 0;
  assert(Math.abs(memoryDisplay.bar - expectedMemoryPct) <= 0.2 &&
      Math.abs(memoryDisplay.ring - expectedMemoryPct) <= 0.2 &&
      memoryDisplay.detail.includes('容量'),
    `Memory allocation visuals are incorrect: ${JSON.stringify({ ...memoryDisplay, expectedMemoryPct })}`);
  await sidebarPanel(page, 'overview').click();
  await page.waitForFunction(() => {
    const button = document.querySelector('#btnCheckTunnel');
    return button && getComputedStyle(button).visibility !== 'hidden' && button.getClientRects().length > 0;
  });
  await page.locator('#btnCheckTunnel').click();
  await page.waitForFunction(() => !document.querySelector('#btnCheckTunnel')?.disabled);
  const tunnel = await page.evaluate(async () => {
    const response = await fetch('/api/tunnel');
    return response.json();
  });
  assert(tunnel.ok, 'Tunnel API did not return a valid evidence result.');
  const tunnelLabels = {
    absent: '未检测到客户端',
    starting: '正在建立连接',
    'local-not-ready': '本地 UDP 未监听',
    'network-unobserved': '本地网络证据未观察到',
    'control-disconnected': '节点控制连接断开',
    ready: '隧道已启动，等待外部验证',
    degraded: '隧道已启动，但数据连接异常',
    verified: '外部数据连接已验证'
  };
  serviceStatusText = await page.locator('#serviceList').innerText();
  assert(serviceStatusText.includes(tunnelLabels[tunnel.state] || tunnel.state),
    `Tunnel state was not rendered from current evidence: ${tunnel.state}.`);
  const endpointText = await page.locator('#tunnelEndpoint').innerText();
  if (tunnel.externalEndpoint) {
    assert(endpointText.includes(tunnel.externalEndpoint), 'Tunnel endpoint differs from the current evidence result.');
  } else {
    assert(endpointText.includes('未从日志识别远程地址'), 'Missing tunnel endpoint was not explained.');
  }
  const lastErrorText = await page.locator('#tunnelLastError').innerText();
  if (tunnel.networkProbeObserved === false) {
    assert(lastErrorText.includes('网络证据探针'),
      'Unobserved local network evidence was presented without its timeout boundary.');
  } else if (tunnel.lastError && !tunnel.lastErrorActive) {
    assert(lastErrorText.includes('历史异常'), 'Historical tunnel error was not preserved as history.');
  } else if (tunnel.lastErrorActive) {
    assert(lastErrorText.includes('最近异常'), 'Active tunnel error was not rendered as current.');
  } else {
    assert(lastErrorText.includes('没有“朋友成功连入/外部流量成功”的证据'),
      'Unverified tunnel state did not keep the external-traffic evidence boundary visible.');
  }
  const dashboard = await page.evaluate(async () => {
    const response = await fetch('/api/dashboard');
    return response.json();
  });
  const warningShown = await page.locator('#dashboardWarnings')
    .evaluate(element => element.classList.contains('show'));
  assert(warningShown === (Array.isArray(dashboard.warnings) && dashboard.warnings.length > 0),
    'Dashboard warning rail does not match the current backend warnings.');
  const playerTimes = await page.evaluate(async () => {
    const response = await fetch('/api/player-times');
    return response.json();
  });
  assert(playerTimes.ok && Array.isArray(playerTimes.players),
    'Player online-time API did not return a valid view.');
  const playerTimeFormat = await page.evaluate(() => ({
    seconds: formatDuration(59),
    minute: formatDuration(65),
    hour: formatDuration(3661),
    day: formatDuration(90061),
  }));
  assert(JSON.stringify(playerTimeFormat) === JSON.stringify({
    seconds: '59s', minute: '1m 5s', hour: '1h 1m', day: '1d 1h',
  }), `Player duration formatting is incorrect: ${JSON.stringify(playerTimeFormat)}`);
  await page.evaluate(() => renderPlayerTimes({
    players: [{
      name: 'Synthetic Player', totalSeconds: 90061, currentSessionSeconds: 3661,
      isOnline: true, connectionState: 'online', sessionCount: 2, lastSeen: new Date().toISOString(),
    }],
    lastObservedAt: new Date().toISOString(), observationState: 'fresh',
  }));
  assert(await page.locator('#playerTimesWrap .player-times-table tbody tr').count() === 1,
    'Player online-time table did not render a synthetic row.');
  const playerTimeRow = await page.locator('#playerTimesWrap').innerText();
  assert(playerTimeRow.includes('Synthetic Player') && playerTimeRow.includes('1d 1h') &&
      playerTimeRow.includes('1h 1m') && playerTimeRow.includes('2'),
    `Player online-time row is incomplete: ${playerTimeRow}`);
  await page.evaluate(() => renderPlayerTimes({
    players: [{
      name: 'Stale Synthetic Player', totalSeconds: 90061, currentSessionSeconds: 0,
      isOnline: false, connectionState: 'unknown', sessionCount: 2, lastSeen: new Date().toISOString(),
    }],
    lastObservedAt: new Date(Date.now() - 181000).toISOString(), observationState: 'stale',
  }));
  const stalePlayerTimeText = await page.locator('#playerTimesCard').innerText();
  assert(stalePlayerTimeText.includes('采集已过期，在线状态未知') &&
      stalePlayerTimeText.includes('状态未知') && !stalePlayerTimeText.includes('1h 1m'),
    `Stale player time was presented as active: ${stalePlayerTimeText}`);
  await page.evaluate(() => refreshPlayerTimes());
  assert(browserErrors.length === 0, browserErrors.join('\n'));
  console.log('UI_STEP=dashboard-asserted');
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    const main = document.querySelector('.main');
    if (main) main.scrollTop = 0;
  });
  await page.screenshot({
    path: path.join(outputDir, 'palworld-dashboard-desktop.png'),
  });

  await sidebarPanel(page, 'settings').click();
  try {
    await page.waitForFunction(() => document.querySelectorAll('#settingsGrid .field').length > 0);
  } catch (error) {
    const gridText = await page.locator('#settingsGrid').innerText().catch(() => '');
    throw new Error(`Settings did not render. Grid: ${gridText}. Browser: ${browserErrors.join(' | ') || 'none'}`);
  }
  const supportedText = await page.locator('#settingsSummary').innerText();
  assert(supportedText.includes('205'), 'Supported settings count is not visible.');
  assert(await page.locator('#f_ADMIN_PASSWORD').getAttribute('type') === 'password', 'Admin password is not write-only UI.');
  assert(await page.locator('#f_ADMIN_PASSWORD').inputValue() === '', 'Admin password was echoed into the browser.');

  await page.locator('label.filter-toggle:has(#showAdvanced)').click();
  await page.waitForTimeout(150);
  assert(await page.locator('#settingsGrid .field').count() === 205, 'Not all supported settings were rendered.');
  assert(await page.locator('#settingsGrid [data-setting-help]').count() === 205, 'Not every setting has a help block.');
  const incompleteHelp = await page.locator('#settingsGrid [data-setting-help]').evaluateAll(elements =>
    elements.filter(element =>
      element.querySelectorAll('.field-help-line').length !== 2 ||
      !element.querySelector('.field-help-source')?.getAttribute('href') ||
      element.textContent.trim().length < 40
    ).map(element => element.getAttribute('data-setting-help'))
  );
  assert(incompleteHelp.length === 0, `Incomplete setting help: ${incompleteHelp.join(', ')}`);
  const fontSizes = await page.evaluate(() => ({
    body: parseFloat(getComputedStyle(document.body).fontSize),
    settingName: parseFloat(getComputedStyle(document.querySelector('.field-topline .name')).fontSize),
    settingHelp: parseFloat(getComputedStyle(document.querySelector('.field-help-line')).fontSize),
  }));
  assert(fontSizes.body >= 17 && fontSizes.settingName >= 17 && fontSizes.settingHelp >= 14,
    `Typography hierarchy is too small: ${JSON.stringify(fontSizes)}`);
  await page.locator('#searchInput').fill('VOICE_CHAT');
  await page.waitForTimeout(100);
  assert(await page.locator('[data-fkey="ENABLE_VOICE_CHAT"]').count() === 1, 'Settings search did not find voice chat.');
  await page.locator('label[for="f_ENABLE_VOICE_CHAT"]').click();
  assert(await page.locator('#saveDock').evaluate(element => element.classList.contains('show')), 'Modified-state save dock did not appear.');
  await page.locator('#btnResetDock').click();
  assert(!(await page.locator('#saveDock').evaluate(element => element.classList.contains('show'))), 'Reset did not clear modified state.');
  console.log('UI_STEP=settings-asserted');
  await page.waitForTimeout(3800);
  await page.screenshot({
    path: path.join(outputDir, 'palworld-settings-desktop.png'),
  });

  await sidebarPanel(page, 'logs').click();
  const insightsLoaded = await page.waitForFunction(
    () => document.querySelectorAll('#logBody .insight-entry').length > 0,
    null,
    { timeout: allowUnhealthyEnvironment ? 2500 : 15000 }
  ).then(() => true).catch(() => false);
  if (!insightsLoaded && !allowUnhealthyEnvironment) {
    throw new Error('Log explanation did not load in the healthy-runtime smoke environment.');
  }
  if (!insightsLoaded) {
    console.log('UI_ENVIRONMENT_WARNING=live-log-insights-not-available');
  }
  assert(await page.locator('#smartLogs').isChecked(), 'Smart log explanation is not enabled by default.');
  assert(await page.locator('#logSummary .log-summary-card').count() === 4, 'Log summary cards are incomplete.');
  assert(await page.locator('#incidentList').count() === 1, 'Incident journal panel is missing.');
  await page.waitForFunction(() => document.querySelectorAll('#logArchiveList .archive-item').length > 0);
  assert((await page.locator('#archivePanelNote').innerText()).includes('00:00–24:00'),
    'Daily archive time boundary is not visible.');
  await page.locator('#btnRefreshArchives').click();
  await page.waitForFunction(() => !document.querySelector('#btnRefreshArchives')?.disabled);
  const archiveDownload = await page.evaluate(async () => {
    const link = document.querySelector('#logArchiveList .archive-download');
    if (!link) return { ok: false, text: '', disposition: '' };
    const response = await fetch(link.getAttribute('href'));
    return {
      ok: response.ok,
      text: await response.text(),
      disposition: response.headers.get('content-disposition') || '',
    };
  });
  assert(archiveDownload.ok &&
      archiveDownload.disposition.includes('attachment') &&
      archiveDownload.text.includes('Palworld Server Daily Log Archive') &&
      archiveDownload.text.includes('[GAME CONTAINER]') &&
      archiveDownload.text.includes('[SAKURAFRP]'),
    'Daily log archive download is incomplete.');
  console.log('UI_STEP=logs-asserted');
  await page.screenshot({
    path: path.join(outputDir, 'palworld-logs-desktop.png'),
  });

  await sidebarPanel(page, 'rcon').click();
  assert(await page.locator('#rconCmdList .rcon-cmd-item').count() === 12, 'Official quick command set is incomplete.');
  assert((await page.locator('#rconCmdList').innerText()).includes('teleporttoplayer'), 'Teleport quick commands are missing.');
  console.log('UI_STEP=rcon-asserted');

  await sidebarPanel(page, 'settings').click();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.locator('#searchInput').fill('');
  await page.waitForTimeout(100);
  const overflow = await page.evaluate(() => {
    const main = document.querySelector('.main');
    const mainRect = main.getBoundingClientRect();
    const offenders = [...main.querySelectorAll('*')].map(element => {
      const rect = element.getBoundingClientRect();
      return {
        tag: element.tagName,
        id: element.id,
        className: String(element.className || '').slice(0, 80),
        right: Math.round(rect.right - mainRect.right),
        own: Math.round(element.scrollWidth - element.clientWidth),
      };
    }).filter(item => item.right > 2 || item.own > 2)
      .sort((a, b) => Math.max(b.right, b.own) - Math.max(a.right, a.own))
      .slice(0, 8);
    return {
      document: document.documentElement.scrollWidth - window.innerWidth,
      main: main.scrollWidth - main.clientWidth,
      offenders,
    };
  });
  assert(overflow.document <= 2 && overflow.main <= 2, `Mobile layout overflows: ${JSON.stringify(overflow)}.`);
  await page.screenshot({
    path: path.join(outputDir, 'palworld-settings-mobile.png'),
  });

  assert(browserErrors.length === 0, browserErrors.join('\n'));
  console.log('UI_SMOKE_ERRORS=0');
  console.log('UI_SUPPORTED_SETTINGS=205');
  console.log(`UI_ARTIFACTS=${outputDir}`);
  await shutdownBrowser();
})().catch(async error => {
  console.error(error.stack || error.message);
  await shutdownBrowser();
  process.exitCode = 1;
});

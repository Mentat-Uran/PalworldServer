#!/usr/bin/env node
'use strict';

// Keeps the no-command operator workflow explicit and regression-testable
// without requiring a running browser or a Palworld server.
const fs = require('fs');
const path = require('path');

const projectDir = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(projectDir, 'web', 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(projectDir, 'web', 'index.html'), 'utf8');
const panel = fs.readFileSync(path.join(projectDir, 'settings-panel.ps1'), 'utf8');

function requireText(source, text, message) {
  if (!source.includes(text)) throw new Error(message);
}

for (const action of ['save', 'backup', 'players', 'tunnel', 'logs']) {
  requireText(index, `data-guide-action="${action}"`, `Overview guide action "${action}" is missing.`);
}
requireText(app, 'async function saveWorld()', 'Overview save action must share a reusable handler.');
requireText(app, 'async function checkTunnel()', 'Overview tunnel action must share a reusable handler.');
requireText(app, 'function configuredPortAction()', 'Port diagnostics must derive its message from the configured endpoints.');
requireText(app, "if (entry.actionCode === 'checkPorts') return configuredPortAction();", 'Port diagnostics must not use fixed default port text.');
requireText(app, 'function focusPlayerTable()', 'Overview player action must lead to the live player table.');
requireText(app, "case 'logs': activatePanel('logs');", 'Overview diagnostics action must open the logs panel.');
requireText(index, 'id="btnRconGuidePlayers"', 'RCON player guide is missing.');
requireText(index, 'id="btnRconGuideInfo"', 'RCON information guide is missing.');
requireText(index, 'id="btnRconPrepareBroadcast"', 'RCON announcement builder is missing.');
requireText(app, 'function rconConfirmationFor(command)', 'High-risk RCON confirmation classifier is missing.');
requireText(app, "['kickplayer', 'banplayer', 'unbanplayer']", 'Player-management confirmation coverage is incomplete.');
requireText(app, "['shutdown', 'doexit']", 'Runtime-stop confirmation coverage is incomplete.');
requireText(app, 'const confirmed = await showModal', 'High-risk RCON commands must require confirmation before dispatch.');
requireText(app, "fillRconCommand(`broadcast ${message}`)", 'Announcement builder must only fill the command input.');
requireText(app, "$('settingsNotice').textContent = t('settings.notice');", 'Settings notice must use the shared runtime-neutral translation.');
requireText(app, 'Applying changes restarts the active service and disconnects players.', 'Settings notice must describe the active service, not Docker only.');
requireText(app, "isWin ? 'stat.cpu.ring.windows' : 'stat.cpu.ring.docker'", 'CPU ring accessibility text must distinguish Windows host capacity from Docker allocation.');
requireText(app, "'stat.cpu.ring.windows': 'CPU {cores} 核主机进程占用 {pct}%'", 'Windows CPU ring translation is missing.');
requireText(app, "'stat.cpu.ring.docker': 'CPU allocation usage {pct}% of {cores} cores'", 'Docker CPU ring English translation is missing.');
requireText(app, "$('langToggle').addEventListener('click', toggleLang);", 'Language toggle must invoke the locale-switching handler.');
requireText(app, 'isWin ? runtimeActiveLabel(s.runtime) : imageName', 'Runtime overview must use the localized runtime label.');
requireText(app, 'function updateRuntimeSwitchControls(state)', 'Runtime switch controls must derive their safety state from the active runtime.');
requireText(app, 'button.disabled = switching || isCurrent;', 'The active runtime switch target must be non-executable.');
requireText(app, "'runtime.btn.current.docker'", 'Docker current-runtime label is missing.');
requireText(app, "'runtime.btn.current.windows'", 'Windows current-runtime label is missing.');
requireText(index, 'id="runtimeSwitchHint"', 'Runtime switch safety hint is missing.');
requireText(app, 'updateRuntimeSwitchControls(runtimeState);', 'Language changes must preserve stateful runtime safety labels.');
requireText(app, "'A runtime switch is in progress; runtime write actions are locked.'", 'Runtime-switch lock explanation is missing.');
requireText(app, 'btn.disabled = switching;', 'Snapshot restore controls must also lock during a runtime switch.');
requireText(panel, 'code = "runtime-already-active"', 'Runtime API must reject same-target switch requests before creating a task.');
requireText(panel, 'The requested runtime is already active. No switch task was created.', 'Runtime API same-target rejection must explain that no task was created.');
requireText(panel, 'function Get-TunnelNetworkProbe', 'Dashboard tunnel probing must be bounded outside the panel process.');
requireText(panel, 'Local network evidence was not observed within the bounded probe timeout.', 'Tunnel network-probe timeout must remain evidence-bounded.');
requireText(panel, "Get-WindowsRuntimeLogs -Lines $lines", 'Windows runtime logs must not fall back to Docker Compose.');
requireText(panel, "source = 'windows native runtime'", 'Windows log source must be explicit in dashboard diagnostics.');
if (app.includes('SakuraFrp is not ready:') || app.includes('SakuraFrp is running, but a newer data-connection error')) {
  throw new Error('Tunnel diagnostics must not hard-code SakuraFrp message prefixes.');
}
if (app.includes('Applying changes recreates the container') || index.includes('重建容器')) {
  throw new Error('Windows-capable settings workflow still exposes a Docker-only restart notice.');
}
for (const staleFallback of ['实时容器指标与快捷操作', '重启容器', '保存后写入文件并重启容器。', '实时容器日志流（最近 300 行）']) {
  if (index.includes(staleFallback)) throw new Error(`Stale Docker-only HTML fallback found: ${staleFallback}`);
}

console.log('CONSOLE_GUIDED_ACTIONS_SOURCE=passed');

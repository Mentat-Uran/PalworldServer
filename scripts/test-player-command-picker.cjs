#!/usr/bin/env node
'use strict';

// Source-contract test for the online-player command picker. It deliberately
// avoids a browser dependency so contributors can validate the privacy and
// runtime-routing boundary on a clean checkout.
const fs = require('fs');
const path = require('path');

const projectDir = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(projectDir, 'web', 'app.js'), 'utf8');
const panel = fs.readFileSync(path.join(projectDir, 'settings-panel.ps1'), 'utf8');

function requireMatch(source, pattern, message) {
  if (!pattern.test(source)) throw new Error(message);
}

requireMatch(app, /const PLAYER_COMMAND_ID_FIELDS = \[/, 'Player command identifier definitions are missing.');
requireMatch(app, /fields: \['steamId', 'steamid', 'steam_id'\]/, 'Steam ID is not a supported command identifier.');
requireMatch(app, /fields: \['playerUserId', 'playeruid', 'playerUid', 'player_uid', 'userId', 'userid'\]/, 'Player UID aliases are incomplete.');
requireMatch(app, /data-player-command-candidate=/, 'Player command controls must use opaque candidate keys.');
requireMatch(app, /playerCommandCandidates\.set\(candidateId, \{ value, name: playerName, kindKey: definition\.key \}\)/, 'Raw player identifiers must remain in the in-memory candidate map.');
if (/data-player-command-(?:value|id)=/.test(app)) {
  throw new Error('Raw player identifiers must not be written into player command HTML data attributes.');
}
requireMatch(app, /function insertPlayerIdIntoRcon\(candidateId\)/, 'Player command insertion handler is missing.');
requireMatch(app, /input\.setRangeText\(candidate\.value/, 'Player ID insertion must use the command input selection API.');
requireMatch(app, /activatePanel\('rcon'\)/, 'Selecting a player identifier must open the command panel.');
requireMatch(app, /placeholder = \/<\(\?:steamid\|playeruid\|playerid\|userid\)>\/i/, 'Known command placeholders are not supported.');
requireMatch(app, /<button type="button" class="rcon-cmd-item"/, 'Quick RCON commands must be semantic buttons.');

requireMatch(panel, /\$runtime = Get-ActiveRuntime[\s\S]*?if \(\$runtime -eq 'windows'\)[\s\S]*?Invoke-WindowsRcon -Command \$cmd -Timeout 10/, 'RCON requests are not routed to the Windows runtime.');
requireMatch(panel, /cmd must be a string\./, 'RCON requests must reject non-string command bodies.');
requireMatch(panel, /RCON command executed: runtime=\$\(Get-ActiveRuntime\); verb=\$commandVerb; ok=\$\(\$result\.ok\)\./, 'RCON audit logging must omit raw command arguments.');

console.log('PLAYER_COMMAND_PICKER_SOURCE=passed');

#!/usr/bin/env node
'use strict';

// The comparison helper is used during maintenance drills. Keep runtime
// backup copies out of its core-world scope so a normal platform transition
// cannot be reported as a false save-loss incident.
const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname, 'compare-save-integrity.ps1'), 'utf8');

function requireText(text, message) {
  if (!source.includes(text)) throw new Error(message);
}

requireText('function Test-TransientSavePath', 'Missing reusable transient-save path classifier.');
requireText('(?:backup|world_save_bak)', 'Core comparison must exclude both backup and world_save_bak directories.');
requireText('Test-TransientSavePath -Path $_.FullName', 'Every core, level, and file-count comparison must use the shared classifier.');
requireText('A byte mismatch against its live SaveGames can result from normal post-snapshot saves or world-time updates', 'Live comparison must explain why a byte mismatch is not corruption proof.');
if (source.includes("DirectoryName -notmatch '\\backup\\'")) {
  throw new Error('Legacy backup-only filtering remains in the integrity comparison helper.');
}

console.log('COMPARE_SAVE_INTEGRITY_SOURCE=passed');

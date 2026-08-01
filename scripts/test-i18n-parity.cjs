#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectDir = path.resolve(__dirname, '..');
const appPath = path.join(projectDir, 'web', 'app.js');
const indexPath = path.join(projectDir, 'web', 'index.html');
const source = fs.readFileSync(appPath, 'utf8');
const indexHtml = fs.readFileSync(indexPath, 'utf8');
const marker = 'const I18N =';
const markerIndex = source.indexOf(marker);

if (markerIndex < 0) {
  throw new Error('I18N declaration was not found in web/app.js.');
}

const objectStart = source.indexOf('{', markerIndex + marker.length);
if (objectStart < 0) {
  throw new Error('I18N object start was not found in web/app.js.');
}

let depth = 0;
let quote = null;
let escaped = false;
let objectEnd = -1;
for (let index = objectStart; index < source.length; index += 1) {
  const character = source[index];
  if (quote !== null) {
    if (escaped) {
      escaped = false;
    } else if (character === '\\') {
      escaped = true;
    } else if (character === quote) {
      quote = null;
    }
    continue;
  }
  if (character === "'" || character === '"' || character === '`') {
    quote = character;
    continue;
  }
  if (character === '{') {
    depth += 1;
  } else if (character === '}') {
    depth -= 1;
    if (depth === 0) {
      objectEnd = index + 1;
      break;
    }
  }
}

if (objectEnd < 0) {
  throw new Error('I18N object was not closed in web/app.js.');
}

const literal = source.slice(objectStart, objectEnd);
let dictionaries;
try {
  dictionaries = Function(`"use strict"; return (${literal});`)();
} catch (error) {
  throw new Error(`Unable to parse the I18N object: ${error.message}`);
}

function flattenKeys(value, prefix = '') {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`Locale dictionary at "${prefix || '<root>'}" must be a plain object.`);
  }
  const keys = [];
  for (const [key, child] of Object.entries(value)) {
    const fullKey = prefix ? `${prefix}.${key}` : key;
    if (child && typeof child === 'object' && !Array.isArray(child)) {
      keys.push(...flattenKeys(child, fullKey));
    } else {
      keys.push(fullKey);
    }
  }
  return keys.sort();
}

if (!dictionaries || typeof dictionaries !== 'object' || !dictionaries.zh || !dictionaries.en) {
  throw new Error('I18N must contain both zh and en locale dictionaries.');
}

const zhKeys = flattenKeys(dictionaries.zh);
const enKeys = flattenKeys(dictionaries.en);
const enSet = new Set(enKeys);
const zhSet = new Set(zhKeys);
const onlyZh = zhKeys.filter((key) => !enSet.has(key));
const onlyEn = enKeys.filter((key) => !zhSet.has(key));
const referencedKeys = new Set();
for (const match of indexHtml.matchAll(/\bdata-i18n(?:-(?:placeholder|title|aria-label))?="([^"]+)"/g)) {
  referencedKeys.add(match[1]);
}
for (const match of source.matchAll(/\bt\(\s*'([^']+)'\s*(?:[,\)])/g)) {
  referencedKeys.add(match[1]);
}
const missingReferences = [...referencedKeys].filter((key) => !zhSet.has(key) || !enSet.has(key)).sort();

console.log(`I18N_ZH_KEYS=${zhKeys.length}`);
console.log(`I18N_EN_KEYS=${enKeys.length}`);
console.log(`I18N_REFERENCED_KEYS=${referencedKeys.size}`);
if (onlyZh.length || onlyEn.length || missingReferences.length) {
  if (onlyZh.length) console.error(`I18N_ONLY_ZH=${onlyZh.join(',')}`);
  if (onlyEn.length) console.error(`I18N_ONLY_EN=${onlyEn.join(',')}`);
  if (missingReferences.length) console.error(`I18N_MISSING_REFERENCES=${missingReferences.join(',')}`);
  process.exitCode = 1;
} else {
  console.log('I18N_PARITY=passed');
}

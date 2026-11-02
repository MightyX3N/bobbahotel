#!/usr/bin/env node
// Writes the Nitro client's two config files for the live hotel, from the ones in nitro/ (which
// point at a local test setup): node deploy/nitro-config.mjs <clientDir> <https://domain>
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [clientDir, site] = process.argv.slice(2);
if (!clientDir || !/^https?:\/\/[^/]+$/.test(site ?? '')) {
  console.error('usage: nitro-config.mjs <clientDir> <https://domain>');
  process.exit(2);
}
const root = fileURLToPath(new URL('..', import.meta.url));
const wsUrl = site.replace(/^http/, 'ws') + '/ws';

const renderer = JSON.parse(readFileSync(join(root, 'nitro', 'renderer-config.json'), 'utf8'));
Object.assign(renderer, {
  'socket.url': wsUrl,
  'asset.url': `${site}/nitro`,
  'image.library.url': `${site}/nitro/c_images/`,
  'hof.furni.url': `${site}/nitro/dcr/hof_furni`,
  'system.log.debug': false,
  'system.log.warn': false,
});
writeFileSync(join(clientDir, 'renderer-config.json'), JSON.stringify(renderer, null, 1));

const ui = JSON.parse(readFileSync(join(root, 'nitro', 'ui-config.json'), 'utf8'));
Object.assign(ui, { 'url.prefix': site, 'camera.url': '', 'thumbnails.url': '' });
writeFileSync(join(clientDir, 'ui-config.json'), JSON.stringify(ui, null, 1));
console.log(`Client configs written for ${site}`);

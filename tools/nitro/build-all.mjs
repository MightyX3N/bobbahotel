#!/usr/bin/env node
// Builds everything the Nitro client loads from our pictures, in order:
// rooms and UI bundles, furni (+ their SQL), avatars, UI pictures.
// Usage: node tools/nitro/build-all.mjs <outDir> <spritesDir>
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const [out, sprites] = process.argv.slice(2);
if (!out || !sprites) {
  console.error('usage: build-all.mjs <outDir> <spritesDir>');
  process.exit(2);
}
for (const step of ['build-generic', 'build-furni', 'build-figure', 'build-ui']) {
  execFileSync(process.execPath, [fileURLToPath(new URL(`${step}.mjs`, import.meta.url)), out, sprites], { stdio: 'inherit' });
}

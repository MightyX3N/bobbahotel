#!/usr/bin/env node
// Builds everything the Nitro client loads from our pictures, in order:
// rooms and UI bundles, furni (+ their SQL), pets, avatars, UI pictures.
// Usage: node tools/nitro/build-all.mjs <outDir> <spritesDir>
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const [out, sprites] = process.argv.slice(2);
if (!out || !sprites) {
  console.error('usage: build-all.mjs <outDir> <spritesDir>');
  process.exit(2);
}
// On the server (the database settings are in the environment): first unpack art packs uploaded
// on the admin pages into the sprites folder (web/src/art.ts). This is here and not only in
// deploy/deploy.sh because the server runs the deploy script installed by setup.sh, which only
// changes when setup.sh is run again; this file always comes with the release.
if (process.env.DB_PASSWORD && process.env.DB_NAME) {
  try {
    console.log('Art packs uploaded on the admin pages');
    execFileSync(process.execPath, ['--disable-warning=ExperimentalWarning', fileURLToPath(new URL('../../web/src/art.ts', import.meta.url)), 'apply', sprites], { stdio: 'inherit' });
  } catch {
    console.warn('  could not unpack the uploaded art packs (building with the pictures already there)');
  }
}
for (const step of ['build-generic', 'build-furni', 'build-pets', 'build-figure', 'build-ui']) {
  execFileSync(process.execPath, [fileURLToPath(new URL(`${step}.mjs`, import.meta.url)), out, sprites], { stdio: 'inherit' });
}

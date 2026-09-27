// CI only (see .github/workflows/testflight.yml): switch each target's Release build to manual App Store signing with
// the given team and a provisioning profile per bundle ID. The app and the share extension need a profile each, so the
// settings cannot simply be passed to xcodebuild on the command line, which would apply one profile to both.
import fs from 'fs'; import path from 'path'; import { fileURLToPath } from 'url';
const [team, ...pairs] = process.argv.slice(2);
const profiles = Object.fromEntries(pairs.map(p => p.split('=')));
if (!/^[A-Z0-9]{10}$/.test(team || '') || !pairs.length || Object.values(profiles).some(u => !/^[0-9A-Fa-f-]{36}$/.test(u || ''))) {
  console.error('usage: node scripts/ios-signing.mjs <team id> <bundle id>=<provisioning profile uuid> ...'); process.exit(1);
}
const file = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../TorrentStation.xcodeproj/project.pbxproj');
let src = fs.readFileSync(file, 'utf8');
const blocks = [...src.matchAll(/\/\* Release \*\/ = \{\s*isa = XCBuildConfiguration;[\s\S]*?name = Release;\s*\};/g)]
  .filter(m => m[0].includes('PRODUCT_BUNDLE_IDENTIFIER'));
const unused = new Set(Object.keys(profiles));
for (const block of blocks.reverse()) {
  const bundle = block[0].match(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/)[1];
  if (!profiles[bundle]) { console.error(`no provisioning profile for ${bundle}`); process.exit(1); }
  if (!block[0].includes('CODE_SIGN_STYLE = Automatic;')) { console.error(`${bundle}: Release settings are not automatic signing`); process.exit(1); }
  const indent = block[0].match(/\n(\s*)CODE_SIGN_STYLE/)[1];
  const signed = block[0].replace(/\n\s*DEVELOPMENT_TEAM = [^;]*;/, '').replace('CODE_SIGN_STYLE = Automatic;', ['CODE_SIGN_STYLE = Manual;',
    `DEVELOPMENT_TEAM = ${team};`, `PROVISIONING_PROFILE_SPECIFIER = "${profiles[bundle]}";`, 'CODE_SIGN_IDENTITY = "Apple Distribution";'].join('\n' + indent));
  src = src.slice(0, block.index) + signed + src.slice(block.index + block[0].length);
  unused.delete(bundle);
  console.log(`signing: ${bundle} Release uses team ${team}, profile ${profiles[bundle]}`);
}
if (unused.size) { console.error(`no target has bundle ID ${[...unused].join(', ')}`); process.exit(1); }
fs.writeFileSync(file, src);

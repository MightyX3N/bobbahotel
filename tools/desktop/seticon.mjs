// Puts Bobba Hotel's icon (and name) into love.exe, before the game is joined onto it.
//   node tools/desktop/seticon.mjs <love.exe> <icon.ico>     (npm i resedit pe-library)
import * as ResEdit from "resedit";
import * as PE from "pe-library";
import fs from "fs";
const [exePath, icoPath] = process.argv.slice(2);
const exe = PE.NtExecutable.from(fs.readFileSync(exePath), { ignoreCert: true });
const res = PE.NtExecutableResource.from(exe);
const ico = ResEdit.Data.IconFile.from(fs.readFileSync(icoPath));
for (const g of ResEdit.Resource.IconGroupEntry.fromEntries(res.entries)) {
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, g.id, g.lang, ico.icons.map((i) => i.data));
}
const vi = ResEdit.Resource.VersionInfo.fromEntries(res.entries)[0];
if (vi) {
  for (const lang of vi.getAllLanguagesForStringValues()) {
    vi.setStringValues(lang, { FileDescription: "Bobba Hotel", ProductName: "Bobba Hotel", InternalName: "BobbaHotel", OriginalFilename: "BobbaHotel.exe" });
  }
  vi.outputToResourceEntries(res.entries);
}
res.outputResource(exe);
fs.writeFileSync(exePath, Buffer.from(exe.generate()));

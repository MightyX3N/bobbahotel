# Nitro room parser (vendored)

These files are copied from **nitro-renderer** by billsonnn
(https://github.com/billsonnn/nitro-renderer, commit 9e9a62385b61957645d0899518a9e1293e865fe8), which is licensed under the
**GNU General Public License v3.0**, the same licence as Bobba Hotel.

They work out a room's floor and wall planes (wall pieces, top edges, end pieces) from its
heightmap, exactly as Nitro and Habbo do. Bobba Hotel only uses the resulting plane geometry
and draws it itself (see ../drawRoom.ts).

Changes: only the import lines (pointing at ./api.ts, which provides the few small types and
helpers the parser needs instead of the rest of nitro-renderer), plus a header comment and
`// @ts-nocheck` so the code is used as-is without our stricter type settings.

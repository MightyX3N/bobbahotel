// Starter looks for new players, from the avatar kit's pieces (see tools/nitro/build-figure.mjs:
// set ids are 100 + n for the male pieces and 200 + n for the female ones).
const PIECES = { body: 4, hair: 10, top: 12, bottom: 10, shoes: 10 } as const;

export function starterLook(gender: 'M' | 'F', random: () => number = Math.random): string {
  const base = gender === 'M' ? 100 : 200;
  const pick = (n: number) => base + 1 + Math.floor(random() * n);
  return `hd-${pick(PIECES.body)}.hr-${pick(PIECES.hair)}.ch-${pick(PIECES.top)}.lg-${pick(PIECES.bottom)}.sh-${pick(PIECES.shoes)}`;
}

/** Hotel names: 3-15 letters, digits and - _ . (like Habbo). */
export function validName(name: string): boolean {
  return /^[A-Za-z0-9\-_.]{3,15}$/.test(name) && !/^(mod|admin|staff)[-_.]/i.test(name);
}

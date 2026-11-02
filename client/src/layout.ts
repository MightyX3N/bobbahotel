// Screen layout shared by the room and the windows: how much of the bottom the toolbar takes
// (more on phones, where the chat box gets its own row) and whether this is a small screen.

/** Height of the toolbar along the bottom (0 before it exists). */
export function toolbarHeight(): number {
  return document.querySelector<HTMLElement>('.toolbar')?.offsetHeight ?? 0;
}

/** Phones (and small windows): windows open full width. */
export function isNarrow(): boolean {
  return window.innerWidth < 600;
}

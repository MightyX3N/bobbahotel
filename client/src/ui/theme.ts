// Themes hold only the look (CSS and art); the windows' logic is shared. One theme for now.
// To add one: a new folder under themes/ and an entry here. The admin will pick it server-wide.
const themes = {
  bobba: () => import('../themes/bobba/theme.css'),
} as const;

export type ThemeName = keyof typeof themes;

export async function loadTheme(name: ThemeName = 'bobba'): Promise<void> {
  document.documentElement.dataset.theme = name;
  await themes[name]();
}

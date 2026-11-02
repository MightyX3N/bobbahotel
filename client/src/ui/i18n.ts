// All UI text comes from a language file. Only English exists for now; another language is just
// another JSON file with the same keys (anything missing falls back to English).
import en from './lang/en.json';

type Key = keyof typeof en;
const strings: Record<string, string> = en;

/** Text for a key, with {name} placeholders filled in. */
export function t(key: Key | (string & {}), vars: Record<string, string | number> = {}): string {
  const text = strings[key] ?? (en as Record<string, string>)[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (_, name: string) => String(vars[name] ?? `{${name}}`));
}

// The login screen (Steam or guest) and the "choose your name" screen after a first Steam login.
// Placeholder look; the real one comes with the UI theme.
import { NAME_MAX, NAME_MIN } from '@bobba/shared';
import { post } from './api.ts';
import { t } from './ui/i18n.ts';
import en from './ui/lang/en.json';

const errorText = (code: string) =>
  t(Object.hasOwn(en, `error.${code}`) ? `error.${code}` : 'error.unknown', { min: NAME_MIN, max: NAME_MAX });

const screen = () => document.getElementById('screen')!;

function show(html: string): HTMLElement {
  const el = screen();
  el.innerHTML = `<div class="panel">${html}</div>`;
  el.hidden = false;
  return el;
}

export function hideScreens(): void {
  screen().hidden = true;
  screen().innerHTML = '';
}

/** Shows the login screen; resolves once the player is logged in. */
export function showLogin(failed: boolean): Promise<void> {
  const el = show(`
    <h1>${t('login.title')}</h1>
    <p>${t('login.tagline')}</p>
    <a class="button wide" href="/api/auth/steam">${t('login.steam')}</a>
    <div class="or">${t('login.or_guest')}</div>
    <form>
      <input name="name" maxlength="${NAME_MAX}" placeholder="${t('login.name_placeholder')}" autocomplete="off" spellcheck="false" />
      <button class="button" type="submit">${t('login.play')}</button>
    </form>
    <div class="error" role="alert">${failed ? t('login.steam_failed') : ''}</div>`);
  return nameForm(el, '/api/auth/guest');
}

/** After the first Steam login: pick a hotel name. */
export function showChooseName(): Promise<void> {
  const el = show(`
    <h1>${t('name.title')}</h1>
    <p>${t('name.text')}</p>
    <form>
      <input name="name" maxlength="${NAME_MAX}" placeholder="${t('name.placeholder')}" autocomplete="off" spellcheck="false" />
      <button class="button" type="submit">${t('name.submit')}</button>
    </form>
    <div class="error" role="alert"></div>`);
  return nameForm(el, '/api/auth/name');
}

function nameForm(el: HTMLElement, endpoint: string): Promise<void> {
  const form = el.querySelector('form')!;
  const input = form.querySelector('input')!;
  const error = el.querySelector('.error')!;
  input.focus();
  return new Promise((resolve) => {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const button = form.querySelector('button')!;
      button.disabled = true;
      const problem = await post(endpoint, { name: input.value.trim() });
      button.disabled = false;
      if (problem) {
        error.textContent = errorText(problem);
        input.focus();
        return;
      }
      resolve();
    });
  });
}

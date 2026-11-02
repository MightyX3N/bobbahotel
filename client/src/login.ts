// The login screen (Steam or guest) and the "choose your name" screen after a first Steam login.
// Placeholder look; the real one comes with the UI theme.
import { NAME_MAX, NAME_MIN } from '@bobba/shared';
import { post } from './api.ts';

// Moves into the language files in step 3.
const ERRORS: Record<string, string> = {
  too_short: `Names need at least ${NAME_MIN} characters.`,
  too_long: `Names can have at most ${NAME_MAX} characters.`,
  bad_characters: 'Use letters, numbers and - _ = ? ! @ : . , only.',
  name_taken: 'That name is taken.',
  bad_origin: 'Please open the hotel from its own address.',
  offline: 'Can’t reach the hotel. Try again in a moment.',
};
const errorText = (code: string) => ERRORS[code] ?? 'Something went wrong. Try again.';

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
    <h1>Bobba Hotel</h1>
    <p>Check in, make friends, build your room.</p>
    <a class="button wide" href="/api/auth/steam">Log in with Steam</a>
    <div class="or">or play as a guest</div>
    <form>
      <input name="name" maxlength="${NAME_MAX}" placeholder="Pick a name" autocomplete="off" spellcheck="false" />
      <button class="button" type="submit">Play</button>
    </form>
    <div class="error" role="alert">${failed ? 'Steam login failed. Try again.' : ''}</div>`);
  return nameForm(el, '/api/auth/guest');
}

/** After the first Steam login: pick a hotel name. */
export function showChooseName(): Promise<void> {
  const el = show(`
    <h1>Welcome!</h1>
    <p>Choose your hotel name. Other players will see it.</p>
    <form>
      <input name="name" maxlength="${NAME_MAX}" placeholder="Your name" autocomplete="off" spellcheck="false" />
      <button class="button" type="submit">Check in</button>
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

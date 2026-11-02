// The website's pages: plain HTML, no client-side code needed.

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="icon" href="/client/favicon.ico">
<style>
  :root { --sky: #6eadc8; --sky-dark: #3d7d9a; --ink: #1d2a33; --card: #ffffffee; --green: #3c9a2f; --green-dark: #2b7322; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; font: 15px/1.45 Ubuntu, "Segoe UI", system-ui, sans-serif; color: var(--ink);
    background: linear-gradient(#9fd0e6, var(--sky) 55%, var(--sky-dark)); display: flex; flex-direction: column; align-items: center; }
  header { width: 100%; max-width: 760px; padding: 28px 16px 8px; }
  .logo { font: 800 40px/1 Ubuntu, system-ui, sans-serif; color: #fff; letter-spacing: 1px;
    text-shadow: 0 3px 0 #1d4f66, 0 6px 14px #0004; }
  .logo small { display: block; font-size: 14px; font-weight: 500; letter-spacing: 0; text-shadow: none; opacity: .9; margin-top: 6px; }
  main { width: 100%; max-width: 760px; padding: 16px; }
  .card { background: var(--card); border: 2px solid #1d4f66; border-radius: 10px; padding: 22px; box-shadow: 0 6px 0 #1d4f6655; }
  h1 { margin: 0 0 10px; font-size: 22px; }
  p { margin: 8px 0; }
  .btn { display: inline-block; border: 0; border-radius: 6px; padding: 12px 20px; font: 700 17px Ubuntu, system-ui, sans-serif;
    color: #fff; background: var(--green); box-shadow: 0 4px 0 var(--green-dark); cursor: pointer; text-decoration: none; }
  .btn:hover { filter: brightness(1.08); }
  .btn.steam { background: #171a21; box-shadow: 0 4px 0 #000; }
  .btn.small { padding: 7px 12px; font-size: 14px; background: #7a8a94; box-shadow: 0 3px 0 #56636b; }
  .row { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; margin-top: 16px; }
  label { display: block; font-weight: 700; margin: 14px 0 6px; }
  input[type=text] { width: 100%; max-width: 320px; padding: 10px 12px; font: 16px Ubuntu, system-ui, sans-serif; border: 2px solid #9db3bf; border-radius: 6px; }
  .error { background: #fde3e1; border: 1px solid #e0938b; padding: 8px 12px; border-radius: 6px; margin: 12px 0; }
  .muted { opacity: .7; font-size: 13px; }
  .choice { display: inline-flex; gap: 6px; align-items: center; margin-right: 16px; }
  footer { margin: auto 0 18px; color: #ffffffcc; font-size: 12px; }
  footer a { color: #fff; }
</style>
</head>
<body>
<header><div class="logo">Bobba Hotel<small>A pixel hotel to hang out, build rooms and meet people.</small></div></header>
<main>${body}</main>
<footer>Bobba Hotel runs on <a href="https://github.com/MightyX3N/bobbahotel">open-source software</a>. Not affiliated with Sulake or Habbo.</footer>
</body>
</html>`;
}

export function loginPage(error?: string): string {
  return layout('Bobba Hotel', `
<div class="card">
  <h1>Welcome!</h1>
  <p>Make your avatar, decorate rooms with furni and chat with everyone in the hotel. It's free: you log in with your Steam account.</p>
  ${error ? `<div class="error">${esc(error)}</div>` : ''}
  <div class="row"><a class="btn steam" href="/auth/steam">Log in with Steam</a></div>
</div>`);
}

export function namePage(opts: { error?: string; name?: string; gender?: 'M' | 'F' } = {}): string {
  const g = opts.gender ?? 'M';
  return layout('Choose your name - Bobba Hotel', `
<div class="card">
  <h1>Choose your hotel name</h1>
  <p>This is the name everyone in the hotel sees. You can't change it later.</p>
  ${opts.error ? `<div class="error">${esc(opts.error)}</div>` : ''}
  <form method="post" action="/name">
    <label for="name">Name</label>
    <input id="name" name="name" type="text" required minlength="3" maxlength="15" pattern="[A-Za-z0-9\\-_.]{3,15}" value="${esc(opts.name ?? '')}" autofocus>
    <p class="muted">3 to 15 letters, numbers, or - _ .</p>
    <label>Avatar</label>
    <span class="choice"><input type="radio" id="gm" name="gender" value="M"${g === 'M' ? ' checked' : ''}><label for="gm" style="display:inline;margin:0">Boy</label></span>
    <span class="choice"><input type="radio" id="gf" name="gender" value="F"${g === 'F' ? ' checked' : ''}><label for="gf" style="display:inline;margin:0">Girl</label></span>
    <p class="muted">You get a random outfit to start with; change it any time in the hotel.</p>
    <div class="row"><button class="btn" type="submit">Create my avatar</button></div>
  </form>
  <form method="post" action="/logout" class="row"><button class="btn small" type="submit">Log out</button></form>
</div>`);
}

export function homePage(name: string, isStaff: boolean): string {
  return layout('Bobba Hotel', `
<div class="card">
  <h1>Hi, ${esc(name)}!</h1>
  <p>Your rooms and friends are waiting.</p>
  <div class="row">
    <a class="btn" href="/hotel">Enter the hotel</a>
    ${isStaff ? '<a class="btn small" href="/admin">Admin</a>' : ''}
    <form method="post" action="/logout"><button class="btn small" type="submit">Log out</button></form>
  </div>
</div>`);
}

export { layout, esc };

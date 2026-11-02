import { describe, expect, it } from 'vitest';
import { Auth, readCookie } from '../src/auth.ts';
import { starterLook, validName } from '../src/looks.ts';
import type { Db } from '../src/db.ts';

describe('names and looks', () => {
  it('accepts hotel names like Habbo', () => {
    expect(validName('Bobba')).toBe(true);
    expect(validName('a.b-c_d')).toBe(true);
    expect(validName('ab')).toBe(false);
    expect(validName('sixteen_letters_')).toBe(false);
    expect(validName('has space')).toBe(false);
    expect(validName('MOD-Bob')).toBe(false);
  });

  it('gives starter looks from the right kit', () => {
    expect(starterLook('M', () => 0)).toBe('hd-101.hr-101.ch-101.lg-101.sh-101');
    expect(starterLook('F', () => 0.999)).toBe('hd-204.hr-210.ch-212.lg-210.sh-210');
  });
});

describe('Steam login', () => {
  const site = 'https://hotel.example';
  const params = (over: Record<string, string> = {}) =>
    new URLSearchParams({
      'openid.mode': 'id_res',
      'openid.op_endpoint': 'https://steamcommunity.com/openid/login',
      'openid.return_to': `${site}/auth/steam/return`,
      'openid.claimed_id': 'https://steamcommunity.com/openid/id/76561198000000001',
      'openid.sig': 'x',
      ...over,
    });
  const auth = (answer: string) =>
    new Auth({} as Db, { publicUrl: site, fetch: (async () => new Response(answer)) as typeof fetch });

  it('trusts a login Steam confirms', async () => {
    expect(await auth('ns:...\nis_valid:true\n').verifySteam(params())).toBe('76561198000000001');
  });
  it('refuses one Steam does not confirm', async () => {
    expect(await auth('is_valid:false').verifySteam(params())).toBeNull();
  });
  it('refuses a login meant for another site', async () => {
    expect(await auth('is_valid:true').verifySteam(params({ 'openid.return_to': 'https://evil.example/auth/steam/return' }))).toBeNull();
  });
  it('reads cookies', () => {
    expect(readCookie('a=1; bh_login=xyz; b=2', 'bh_login')).toBe('xyz');
    expect(readCookie(undefined, 'bh_login')).toBeNull();
  });
});

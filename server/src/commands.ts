// Chat commands (text starting with ":"). Staff commands check `staff` themselves.
import type { Users } from './users.ts';

export interface CommandContext {
  staff: boolean;
  users: Users;
  /** Tell the player something (a language-file code with values). */
  reply(code: string, vars?: Record<string, string | number>): void;
  /** An account changed (e.g. got Club): its owner should get fresh account info. */
  accountChanged(userId: number): void;
}

/** Most Club days one command can give. */
const MAX_CLUB_DAYS = 3650;

export function runCommand(text: string, ctx: CommandContext): void {
  const [name = '', ...args] = text.slice(1).split(/\s+/);
  switch (name.toLowerCase()) {
    case 'club': {
      // :club <name> <days>   (staff) give Bobba Club days; negative days take them away
      if (!ctx.staff) return ctx.reply('command.not_allowed');
      const [who, daysText] = args;
      const days = Number(daysText);
      if (!who || !Number.isInteger(days) || days === 0 || Math.abs(days) > MAX_CLUB_DAYS) return ctx.reply('command.club_usage');
      const target = ctx.users.byName(who);
      if (!target) return ctx.reply('command.no_such_user', { name: who });
      const until = ctx.users.addClubDays(target.id, days);
      ctx.accountChanged(target.id);
      return ctx.reply('command.club_given', { name: target.name, days, until: new Date(until).toISOString().slice(0, 10) });
    }
    default:
      return ctx.reply('command.unknown', { name });
  }
}

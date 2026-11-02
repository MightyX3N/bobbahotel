// What the UI can ask for. Set up once the connection exists (see main.ts), so components don't
// need to know about the network.
import type { NavigatorTab } from '@bobba/shared';

export interface UiActions {
  chat(text: string): void;
  loadRooms(tab: NavigatorTab, query: string): void;
  loadLayouts(): void;
  createRoom(name: string, description: string, layout: string): void;
  goToRoom(id: string): void;
  logout(): void;
}

export const actions: UiActions = {
  chat: () => {},
  loadRooms: () => {},
  loadLayouts: () => {},
  createRoom: () => {},
  goToRoom: () => {},
  logout: () => {},
};

export function setActions(a: UiActions): void {
  Object.assign(actions, a);
}

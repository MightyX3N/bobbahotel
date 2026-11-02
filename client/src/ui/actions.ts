// What the UI can ask for. Set up once the connection exists (see main.ts), so components don't
// need to know about the network.
import type { NavigatorTab } from '@bobba/shared';

export interface UiActions {
  chat(text: string): void;
  loadRooms(tab: NavigatorTab, query: string): void;
  loadLayouts(): void;
  createRoom(name: string, description: string, layout: string): void;
  goToRoom(id: string): void;
  saveLayout(plan: { id?: string; name: string; club: boolean; map: string[]; door: [number, number] }): void;
  deleteLayout(id: string): void;
  saveRoomFloor(roomId: string, map: string[], door: [number, number]): void;
  logout(): void;
}

export const actions: UiActions = {
  chat: () => {},
  loadRooms: () => {},
  loadLayouts: () => {},
  createRoom: () => {},
  goToRoom: () => {},
  saveLayout: () => {},
  deleteLayout: () => {},
  saveRoomFloor: () => {},
  logout: () => {},
};

export function setActions(a: UiActions): void {
  Object.assign(actions, a);
}

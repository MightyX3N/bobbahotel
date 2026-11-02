// UI state, kept outside React so the network code can update it. Components read it with useUi().
import { useSyncExternalStore } from 'react';
import type { LayoutInfo, Me, NavigatorTab, RoomInfo } from '@bobba/shared';

export interface UiState {
  me: Me | null;
  room: { id: string; name: string; description: string; owner: string | null; ownerId: number | null; map: string[]; door: [number, number] } | null;
  editorOpen: boolean;
  navigator: {
    open: boolean;
    tab: NavigatorTab | 'create';
    query: string;
    rooms: RoomInfo[];
    loading: boolean;
  };
  layouts: LayoutInfo[];
  /** A short message shown at the top (errors from the server). */
  notice: { text: string; at: number } | null;
  /** The furni clicked in the room (its name and buttons show bottom-right). */
  selectedFurni: { uid: number; name: string; states: number; state: number; wall: boolean } | null;
  /** The furni being placed or moved, while that's going on. */
  placing: { name: string; wall: boolean } | null;
  furniWindowOpen: boolean;
}

let state: UiState = {
  me: null,
  room: null,
  editorOpen: false,
  navigator: { open: false, tab: 'public', query: '', rooms: [], loading: false },
  layouts: [],
  notice: null,
  selectedFurni: null,
  placing: null,
  furniWindowOpen: false,
};
const listeners = new Set<() => void>();

export function getUi(): UiState {
  return state;
}

export function setUi(change: Partial<UiState> | ((s: UiState) => Partial<UiState>)): void {
  state = { ...state, ...(typeof change === 'function' ? change(state) : change) };
  for (const l of listeners) l();
}

export function setNavigator(change: Partial<UiState['navigator']>): void {
  setUi((s) => ({ navigator: { ...s.navigator, ...change } }));
}

export function useUi<T>(pick: (s: UiState) => T): T {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => pick(state),
  );
}

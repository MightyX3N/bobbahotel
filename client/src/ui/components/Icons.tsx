// Our own toolbar icons, drawn as small pixel-style SVGs (17x17 grid, shown at 2x).
const pixel = { shapeRendering: 'crispEdges' as const };

/** Navigator: a little hotel building with lit windows. */
export function NavigatorIcon() {
  return (
    <svg viewBox="0 0 17 17" aria-hidden="true" style={pixel}>
      <rect x="3" y="3" width="11" height="13" fill="#2b3a4a" />
      <rect x="4" y="4" width="9" height="11" fill="#5b87b0" />
      <rect x="2" y="2" width="13" height="2" fill="#c0392b" />
      <rect x="7" y="0" width="3" height="2" fill="#c0392b" />
      {[5, 8, 11].map((x) => [5, 8].map((y) => <rect key={`${x}${y}`} x={x} y={y} width="2" height="2" fill="#ffd966" />))}
      <rect x="7" y="11" width="3" height="5" fill="#6b4226" />
      <rect x="1" y="15" width="15" height="2" fill="#4e7a3a" />
    </svg>
  );
}

/** Furni: a wooden crate. */
export function FurniIcon() {
  return (
    <svg viewBox="0 0 17 17" aria-hidden="true" style={pixel}>
      <rect x="2" y="5" width="13" height="10" fill="#6b4226" />
      <rect x="3" y="6" width="11" height="8" fill="#b07a45" />
      <rect x="3" y="9" width="11" height="1" fill="#6b4226" />
      <rect x="8" y="6" width="1" height="8" fill="#6b4226" />
      <rect x="1" y="3" width="15" height="3" fill="#8a5a30" />
      <rect x="2" y="4" width="13" height="1" fill="#c99560" />
    </svg>
  );
}

/** Zoom: a magnifying glass. */
export function ZoomIcon() {
  return (
    <svg viewBox="0 0 17 17" aria-hidden="true" style={pixel}>
      <rect x="3" y="1" width="6" height="1" fill="#1c1c20" />
      <rect x="1" y="3" width="1" height="6" fill="#1c1c20" />
      <rect x="2" y="2" width="8" height="8" fill="#e8e8e8" />
      <rect x="3" y="3" width="6" height="6" fill="#9fd3ea" />
      <rect x="4" y="4" width="2" height="2" fill="#ffffff" />
      <rect x="10" y="10" width="2" height="2" fill="#6b4226" />
      <rect x="12" y="12" width="3" height="3" fill="#6b4226" />
      <rect x="14" y="14" width="2" height="2" fill="#6b4226" />
    </svg>
  );
}

/** Log out: a door with an arrow. */
export function LogoutIcon() {
  return (
    <svg viewBox="0 0 17 17" aria-hidden="true" style={pixel}>
      <rect x="2" y="1" width="8" height="15" fill="#6b4226" />
      <rect x="3" y="2" width="6" height="13" fill="#9c6b3f" />
      <rect x="7" y="8" width="1" height="2" fill="#ffd966" />
      <rect x="10" y="8" width="5" height="2" fill="#e8e8e8" />
      <rect x="13" y="6" width="1" height="6" fill="#e8e8e8" />
      <rect x="14" y="7" width="1" height="4" fill="#e8e8e8" />
    </svg>
  );
}

/** A tiny person, for user counts. */
export function PersonIcon() {
  return (
    <svg viewBox="0 0 7 9" width="7" height="9" aria-hidden="true" style={pixel}>
      <rect x="2" y="0" width="3" height="3" fill="currentColor" />
      <rect x="1" y="4" width="5" height="3" fill="currentColor" />
      <rect x="1" y="7" width="2" height="2" fill="currentColor" />
      <rect x="4" y="7" width="2" height="2" fill="currentColor" />
    </svg>
  );
}

/** Floor plan editor: a pencil over a tile grid. */
export function FloorPlanIcon() {
  return (
    <svg viewBox="0 0 17 17" aria-hidden="true" style={pixel}>
      <polygon points="1,9 8,5 16,9 8,13" fill="#a47a52" />
      <polygon points="1,9 8,13 8,15 1,11" fill="#7d5a3b" />
      <polygon points="8,13 16,9 16,11 8,15" fill="#5e432c" />
      <line x1="4.5" y1="7" x2="12" y2="11" stroke="#7d5a3b" strokeWidth="0.6" />
      <line x1="12" y1="7" x2="4.5" y2="11" stroke="#7d5a3b" strokeWidth="0.6" />
      <rect x="10" y="1" width="2" height="7" fill="#f2c665" transform="rotate(35 11 4)" />
      <rect x="10" y="7" width="2" height="2" fill="#2b3a4a" transform="rotate(35 11 4)" />
    </svg>
  );
}

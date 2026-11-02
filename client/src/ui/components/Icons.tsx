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

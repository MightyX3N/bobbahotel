// A small picture of a room layout: its floor tiles seen from the room camera, with the door marked.
import { useEffect, useRef } from 'react';
import { parseMap } from '@bobba/shared';

const W = 88;
const H = 56;

export function LayoutPreview({ map, door }: { map: string[]; door: [number, number] }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d')!;
    const grid = parseMap(map);
    const tiles: [number, number, number][] = [];
    grid.forEach((row, y) => row.forEach((h, x) => h >= 0 && tiles.push([x, y, h])));
    // Fit the whole layout: tile size from the layout's extent in screen units.
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const [x, y, h] of tiles) {
      const sx = x - y, sy = (x + y) / 2 - h / 2;
      minX = Math.min(minX, sx - 1); maxX = Math.max(maxX, sx + 1);
      minY = Math.min(minY, sy); maxY = Math.max(maxY, sy + 1);
    }
    const s = Math.min((W - 4) / (maxX - minX), (H - 4) / (maxY - minY));
    const ox = (W - (maxX - minX) * s) / 2 - minX * s;
    const oy = (H - (maxY - minY) * s) / 2 - minY * s;
    ctx.clearRect(0, 0, W, H);
    tiles.sort((a, b) => a[0] + a[1] - (b[0] + b[1]));
    for (const [x, y, h] of tiles) {
      const cx = ox + (x - y) * s;
      const cy = oy + ((x + y) / 2 - h / 2) * s;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + s, cy + s / 2);
      ctx.lineTo(cx, cy + s);
      ctx.lineTo(cx - s, cy + s / 2);
      ctx.closePath();
      ctx.fillStyle = x === door[0] && y === door[1] ? '#1e7295' : h > 0 ? '#c8996b' : '#a47a52';
      ctx.fill();
    }
  }, [map, door]);
  return <canvas ref={ref} width={W} height={H} />;
}

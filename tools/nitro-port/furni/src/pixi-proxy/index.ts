// [bobba] Stand-ins for Nitro's PixiJS helpers (see ../pixi).
import { Container, Rectangle, RenderTexture, Sprite } from '../pixi';

export class NitroContainer extends Container
{
}

export class NitroSprite extends Sprite
{
}

export class PaletteMapFilter
{
    public static CHANNEL_RED: number = 0;
    public static CHANNEL_GREEN: number = 1;
    public static CHANNEL_BLUE: number = 2;
    public static CHANNEL_ALPHA: number = 3;

    public reds: number[];
    public channel: number;

    constructor(reds: number[], channel: number)
    {
        this.reds = reds;
        this.channel = channel;
    }
}

export class AdjustmentFilter
{
    public options: any;

    constructor(options: any = null)
    {
        this.options = options;
    }
}

// Nitro's clock: the avatar code only uses it to see how long ago something was used
let tickerTime = 0;
export function GetTickerTime(): number
{
    return tickerTime;
}

export function SetTickerTime(k: number): void
{
    tickerTime = k;
}

export class TextureUtils
{
    public static generateTexture(container: Container, rect: Rectangle = null): RenderTexture
    {
        const texture = new RenderTexture(null, rect ? rect.width : container.width, rect ? rect.height : container.height);
        texture.container = container;
        return texture;
    }

    // [bobba] pictures as files: not used by the game
    public static generateCanvas(_k: any): any
    {
        return null;
    }

    public static generateImage(_k: any): any
    {
        return null;
    }
}

export class PixiApplicationProxy
{
    public static instance: any = {
        renderer: {
            render: (container: Container, options: any): void =>
            {
                if(options && options.renderTexture) options.renderTexture.container = container;
            }
        }
    };
}

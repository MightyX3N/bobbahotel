// [bobba] Stand-ins for the PixiJS classes Nitro's avatar code uses. They do no drawing: they keep
// the tree of containers and sprites Nitro builds (positions, flips, tints) so Avatar.ts can turn
// it into a list of pictures to draw. Sizes and bounds work the way PixiJS works them out.

export class Point
{
    public x: number;
    public y: number;

    constructor(x: number = 0, y: number = 0)
    {
        this.x = x;
        this.y = y;
    }

    public clone(): Point
    {
        return new Point(this.x, this.y);
    }

    public set(x: number = 0, y: number = x): void
    {
        this.x = x;
        this.y = y;
    }
}

export class Rectangle
{
    public x: number;
    public y: number;
    public width: number;
    public height: number;

    constructor(x: number = 0, y: number = 0, width: number = 0, height: number = 0)
    {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    public get left(): number { return this.x; }
    public get right(): number { return this.x + this.width; }
    public get top(): number { return this.y; }
    public get bottom(): number { return this.y + this.height; }

    public clone(): Rectangle
    {
        return new Rectangle(this.x, this.y, this.width, this.height);
    }

    // PixiJS: the smallest rectangle around both (so a new Rectangle() always takes in 0,0)
    public enlarge(r: Rectangle): Rectangle
    {
        const x1 = Math.min(this.x, r.x);
        const x2 = Math.max(this.x + this.width, r.x + r.width);
        const y1 = Math.min(this.y, r.y);
        const y2 = Math.max(this.y + this.height, r.y + r.height);

        this.x = x1;
        this.width = x2 - x1;
        this.y = y1;
        this.height = y2 - y1;

        return this;
    }
}

export class Matrix
{
    public a: number = 1;
    public b: number = 0;
    public c: number = 0;
    public d: number = 1;
    public tx: number = 0;
    public ty: number = 0;
}

export type Resource = any;

export class BaseTexture
{
}

export class Texture<R = any>
{
    public static EMPTY: Texture = new Texture(null, 1, 1);

    public name: string;
    public width: number;
    public height: number;
    public valid: boolean = true;
    public baseTexture: BaseTexture = new BaseTexture();

    constructor(name: string = null, width: number = 1, height: number = 1)
    {
        this.name = name;
        this.width = width;
        this.height = height;
    }

    public destroy(_k: boolean = false): void
    {
    }

    public static from(_k: any): Texture
    {
        return null;
    }
}

export class RenderTexture extends Texture
{
    public container: Container = null;
}

// What a container or sprite's matrix is: PixiJS keeps position/scale/skew; a matrix with a = -1
// (a flipped sprite) is the same picture either way, so the matrix is kept as it is.
export class Transform
{
    public owner: DisplayObject;

    constructor(owner: DisplayObject)
    {
        this.owner = owner;
    }

    public setFromMatrix(m: Matrix): void
    {
        const o = this.owner;
        o.matrix.a = m.a;
        o.matrix.b = m.b;
        o.matrix.c = m.c;
        o.matrix.d = m.d;
        o.matrix.tx = m.tx;
        o.matrix.ty = m.ty;
        o.position.x = m.tx;
        o.position.y = m.ty;
    }
}

export class DisplayObject
{
    public matrix: Matrix = new Matrix();
    public position: Point;
    public transform: Transform;
    public filters: any[] = null;
    public parent: Container = null;

    constructor()
    {
        this.position = new Point();
        this.transform = new Transform(this);
    }

    // the matrix with the position (position can be set on its own, as PixiJS allows)
    public localMatrix(): Matrix
    {
        const m = new Matrix();
        m.a = this.matrix.a;
        m.b = this.matrix.b;
        m.c = this.matrix.c;
        m.d = this.matrix.d;
        m.tx = this.position.x;
        m.ty = this.position.y;
        return m;
    }

    public destroy(_k: any = null): void
    {
    }
}

export class Container extends DisplayObject
{
    public children: DisplayObject[] = [];

    public addChild<T extends DisplayObject>(child: T): T
    {
        child.parent = this;
        this.children.push(child);
        return child;
    }

    // PixiJS: the box around every sprite inside, in this container's own space
    public getLocalBounds(): Rectangle
    {
        let minX = Infinity;
        let minY = Infinity;
        let maxX = -Infinity;
        let maxY = -Infinity;
        const walk = (o: DisplayObject, a: number, b: number, c: number, d: number, tx: number, ty: number): void =>
        {
            if(o instanceof Sprite)
            {
                const w = o.texture.width * o.scaleX;
                const h = o.texture.height * o.scaleY;
                const pts = [ 0, 0, w, 0, w, h, 0, h ];
                for(let i = 0; i < 8; i += 2)
                {
                    const x = a * pts[i] + c * pts[i + 1] + tx;
                    const y = b * pts[i] + d * pts[i + 1] + ty;
                    if(x < minX) minX = x;
                    if(x > maxX) maxX = x;
                    if(y < minY) minY = y;
                    if(y > maxY) maxY = y;
                }
            }
            else if(o instanceof Container)
            {
                for(const child of o.children)
                {
                    const m = child.localMatrix();
                    walk(child, a * m.a + c * m.b, b * m.a + d * m.b, a * m.c + c * m.d, b * m.c + d * m.d, a * m.tx + c * m.ty + tx, b * m.tx + d * m.ty + ty);
                }
            }
        };
        walk(this, 1, 0, 0, 1, 0, 0);
        if(minX === Infinity) return new Rectangle(0, 0, 0, 0);
        return new Rectangle(minX, minY, maxX - minX, maxY - minY);
    }

    public get width(): number
    {
        return this.getLocalBounds().width;
    }

    public get height(): number
    {
        return this.getLocalBounds().height;
    }
}

export class Sprite extends Container
{
    public texture: Texture;
    public alpha: number = 1;
    public x: number = 0;
    public y: number = 0;
    public blendMode: number = 0;
    public scale: { x: number, y: number } = { x: 1, y: 1 };
    public tint: number = 0xFFFFFF;
    public scaleX: number = 1;
    public scaleY: number = 1;

    constructor(texture: Texture = null)
    {
        super();
        this.texture = texture || Texture.EMPTY;
    }

    // PixiJS: setting the size scales the picture
    public set width(value: number)
    {
        this.scaleX = value / this.texture.width;
    }

    public get width(): number
    {
        return this.texture.width * this.scaleX;
    }

    public set height(value: number)
    {
        this.scaleY = value / this.texture.height;
    }

    public get height(): number
    {
        return this.texture.height * this.scaleY;
    }
}

export class ColorMatrixFilter
{
    public matrix: number[] = [];
}

export enum BLEND_MODES { NORMAL = 0, ADD = 1, MULTIPLY = 2, SCREEN = 3, DARKEN = 6, SUBTRACT = 28 }

export class Filter
{
}

// [bobba] Stand-ins for Nitro's events (nothing listens to them here).
export class NitroEvent
{
    public type: string;

    constructor(type: string)
    {
        this.type = type;
    }
}

export class AvatarRenderEvent extends NitroEvent
{
    public static AVATAR_RENDER_READY: string = 'AVATAR_RENDER_READY';
}

export class AvatarRenderLibraryEvent extends NitroEvent
{
    public static DOWNLOAD_COMPLETE: string = 'ARLE_DOWNLOAD_COMPLETE';
    public library: any;

    constructor(type: string, library: any = null)
    {
        super(type);
        this.library = library;
    }
}

export class AvatarRenderEffectLibraryEvent extends NitroEvent
{
    public static DOWNLOAD_COMPLETE: string = 'AREL_DOWNLOAD_COMPLETE';
    public library: any;

    constructor(type: string, library: any = null)
    {
        super(type);
        this.library = library;
    }
}

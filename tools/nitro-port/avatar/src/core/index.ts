// [bobba] Stand-ins for Nitro's core: events go nowhere, logging is off.
export class EventDispatcher
{
    private _disposed: boolean = false;

    public get disposed(): boolean
    {
        return this._disposed;
    }

    public dispatchEvent(_event: any): boolean
    {
        return true;
    }

    public addEventListener(_type: string, _callback: any): void
    {
    }

    public removeEventListener(_type: string, _callback: any): void
    {
    }

    public removeAllListeners(): void
    {
    }

    public dispose(): void
    {
        this._disposed = true;
    }
}

export class NitroManager extends EventDispatcher
{
}

export class NitroLogger
{
    public static log(..._args: any[]): void
    {
    }

    public static warn(..._args: any[]): void
    {
    }

    public static error(..._args: any[]): void
    {
    }
}

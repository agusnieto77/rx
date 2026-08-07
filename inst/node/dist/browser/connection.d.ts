export declare class DefaultCdpConnection {
    private ws;
    private nextId;
    private pending;
    private eventListeners;
    private _isConnected;
    private commandTimeoutMs;
    constructor();
    get isConnected(): boolean;
    connect(endpointUrl: string): Promise<void>;
    sendCommand(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
    on(event: string, listener: (params: Record<string, unknown>) => void): void;
    removeListener(event: string, listener: (params: Record<string, unknown>) => void): void;
    close(): void;
    private handleMessage;
}

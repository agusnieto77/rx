export interface CdpConnection {
    /** Whether the WebSocket is currently open. */
    readonly isConnected: boolean;
    /** Connect to the given CDP endpoint URL. */
    connect(endpointUrl: string): Promise<void>;
    /** Send a CDP command and wait for its response. */
    sendCommand(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
    /** Close the WebSocket and reject all pending commands. */
    close(): void;
}
export interface CdpConnectionOptions {
    /** Optional timeout in ms for each CDP command (default: 15000). */
    commandTimeoutMs?: number;
}
export declare class DefaultCdpConnection implements CdpConnection {
    private ws;
    private nextId;
    private pending;
    private eventListeners;
    private _isConnected;
    private commandTimeoutMs;
    constructor(options?: CdpConnectionOptions);
    get isConnected(): boolean;
    connect(endpointUrl: string): Promise<void>;
    sendCommand(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
    on(event: string, listener: (params: Record<string, unknown>) => void): void;
    removeListener(event: string, listener: (params: Record<string, unknown>) => void): void;
    /** Register a one-shot listener that is automatically removed after firing once. */
    once(event: string, listener: (params: Record<string, unknown>) => void): void;
    close(): void;
    private handleMessage;
}

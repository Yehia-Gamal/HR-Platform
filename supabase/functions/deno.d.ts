// Ambient type declarations for Deno runtime in Supabase Edge Functions

declare namespace Deno {
  export interface Env {
    get(key: string): string | undefined;
    set(key: string, value: string): void;
    has(key: string): boolean;
    delete(key: string): void;
    toObject(): Record<string, string>;
  }

  export const env: Env;

  export interface ServeHandlerInfo {
    remoteAddr?: {
      transport: "tcp" | "udp";
      hostname: string;
      port: number;
    };
  }

  export type ServeHandler = (
    request: Request,
    info?: ServeHandlerInfo
  ) => Response | Promise<Response>;

  export interface ServeOptions {
    port?: number;
    hostname?: string;
    signal?: AbortSignal;
    onError?: (error: unknown) => Response | Promise<Response>;
    onListen?: (params: { hostname: string; port: number }) => void;
  }

  export function serve(handler: ServeHandler): void;
  export function serve(options: ServeOptions, handler: ServeHandler): void;
}

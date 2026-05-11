import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { URL } from "node:url";
import type { Config } from "./config.js";
import { decodeCursor } from "./cursor.js";
import { registrationYaml } from "./registration.js";
import { SseHub } from "./sseHub.js";
import type { StorageProvider } from "./storage.js";
import type { AppserviceTransaction, RawMatrixEvent } from "./types.js";

type Json = Record<string, unknown> | unknown[];

function sendJson(response: ServerResponse, status: number, body: Json): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function sendText(response: ServerResponse, status: number, body: string, contentType = "text/plain"): void {
  response.writeHead(status, { "content-type": contentType });
  response.end(body);
}

function notFound(response: ServerResponse): void {
  sendJson(response, 404, { error: "not_found" });
}

function methodNotAllowed(response: ServerResponse): void {
  sendJson(response, 405, { error: "method_not_allowed" });
}

function getToken(request: IncomingMessage, url: URL): string | null {
  const auth = request.headers.authorization;
  if (auth?.startsWith("Bearer ")) {
    return auth.slice("Bearer ".length);
  }
  return url.searchParams.get("access_token");
}

function requireHomeserverToken(request: IncomingMessage, url: URL, response: ServerResponse, config: Config): boolean {
  if (getToken(request, url) === config.hsToken) {
    return true;
  }
  sendJson(response, 401, { error: "unauthorized" });
  return false;
}

async function readJson<T>(request: IncomingMessage): Promise<T> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8")) as T;
}

function splitPath(pathname: string): string[] {
  return pathname.split("/").filter(Boolean).map((part) => decodeURIComponent(part));
}

function parseLimit(url: URL): number {
  const raw = url.searchParams.get("limit");
  if (!raw) return 100;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return 100;
  return Math.max(1, Math.min(parsed, 500));
}

function logReceivedEvents(config: Config, txnId: string, events: RawMatrixEvent[]): void {
  if (config.receiveLogLevel === "off") return;

  console.log(`received Matrix appservice transaction ${txnId} with ${events.length} event(s)`);
  for (const event of events) {
    console.log(
      [
        "received Matrix event",
        `event_id=${typeof event.event_id === "string" ? event.event_id : "<missing>"}`,
        `room_id=${typeof event.room_id === "string" ? event.room_id : "<missing>"}`,
        `type=${typeof event.type === "string" ? event.type : "<missing>"}`,
        `sender=${typeof event.sender === "string" ? event.sender : "<missing>"}`,
        `origin_server_ts=${typeof event.origin_server_ts === "number" ? event.origin_server_ts : "<missing>"}`
      ].join(" ")
    );
    if (config.receiveLogLevel === "json") {
      console.log(JSON.stringify(event));
    }
  }
}

export function createHttpServer(config: Config, storage: StorageProvider, sse: SseHub = new SseHub()): Server {
  return createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", "http://localhost");
    const parts = splitPath(url.pathname);

    try {
      if (request.method === "GET" && url.pathname === "/healthz") {
        sendJson(response, 200, { ok: true });
        return;
      }

      if (request.method === "GET" && url.pathname === "/registration.yaml") {
        sendText(response, 200, registrationYaml(config), "application/yaml");
        return;
      }

      if (parts[0] === "_matrix" && parts[1] === "app" && parts[2] === "v1") {
        if (!requireHomeserverToken(request, url, response, config)) return;

        if (request.method === "POST" && parts[3] === "ping") {
          sendJson(response, 200, {});
          return;
        }

        if (request.method === "GET" && parts[3] === "users" && parts[4]) {
          sendJson(response, 404, { errcode: "M_NOT_FOUND", error: "User not managed by repeater" });
          return;
        }

        if (request.method === "GET" && parts[3] === "rooms" && parts[4]) {
          sendJson(response, 404, { errcode: "M_NOT_FOUND", error: "Room alias not managed by repeater" });
          return;
        }

        if (request.method === "PUT" && parts[3] === "transactions" && parts[4]) {
          const txn = await readJson<AppserviceTransaction>(request);
          const events = Array.isArray(txn.events) ? txn.events : [];
          logReceivedEvents(config, parts[4], events);
          const result = await storage.processTransaction(parts[4], events);

          if (!result.duplicate) {
            for (const event of events) {
              sse.publish(event);
            }
          }

          sendJson(response, 200, {});
          return;
        }

        methodNotAllowed(response);
        return;
      }

      if (request.method === "GET" && parts.length === 1 && parts[0] === "rooms") {
        sendJson(response, 200, { rooms: await storage.listRooms() });
        return;
      }

      if (parts[0] === "rooms" && parts[1]) {
        const roomId = parts[1];

        if (request.method === "GET" && parts.length === 3 && parts[2] === "events") {
          const cursor = decodeCursor(url.searchParams.get("from"));
          if (url.searchParams.has("from") && !cursor) {
            sendJson(response, 400, { error: "invalid_cursor" });
            return;
          }

          sendJson(response, 200, await storage.listRoomEvents(roomId, { cursor, limit: parseLimit(url) }));
          return;
        }

        if (request.method === "GET" && parts.length === 4 && parts[2] === "events") {
          const event = await storage.getRoomEvent(roomId, parts[3]);
          if (!event) {
            notFound(response);
            return;
          }
          sendJson(response, 200, event);
          return;
        }

        if (request.method === "GET" && parts.length === 3 && parts[2] === "stream") {
          sse.subscribe(roomId, response);
          return;
        }
      }

      notFound(response);
    } catch (error) {
      const message = error instanceof Error ? error.message : "internal_error";
      sendJson(response, 500, { error: "internal_error", message });
    }
  });
}

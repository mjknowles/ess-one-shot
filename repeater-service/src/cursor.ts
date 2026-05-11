import type { EventCursor } from "./types.js";

export function encodeCursor(cursor: EventCursor): string {
  return Buffer.from(JSON.stringify(cursor), "utf8").toString("base64url");
}

export function decodeCursor(value: string | null): EventCursor | null {
  if (!value) return null;

  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as Partial<EventCursor>;
    if (typeof decoded.ts !== "number" || typeof decoded.event_id !== "string") {
      return null;
    }
    return { ts: decoded.ts, event_id: decoded.event_id };
  } catch {
    return null;
  }
}

import { dirname } from "node:path";
import { mkdirSync } from "node:fs";
import Database from "better-sqlite3";
import { decodeCursor, encodeCursor } from "./cursor.js";
import type { StorageProvider } from "./storage.js";
import type { EventCursor, EventPage, RawMatrixEvent, RoomSummary } from "./types.js";

type EventRow = {
  event_id: string;
  room_id: string;
  origin_server_ts: number;
  raw_json: string;
};

function eventString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function eventNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : Date.now();
}

function getStateContent(event: RawMatrixEvent): Record<string, unknown> {
  return event.content && typeof event.content === "object" ? event.content : {};
}

export class SqliteStorageProvider implements StorageProvider {
  private readonly db: Database.Database;
  private readonly processTransactionSync: (txnId: string, events: RawMatrixEvent[]) => { inserted: number; duplicate: boolean };

  constructor(path: string) {
    if (path !== ":memory:") {
      mkdirSync(dirname(path), { recursive: true });
    }

    this.db = new Database(path);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("foreign_keys = ON");
    this.migrate();

    this.processTransactionSync = this.db.transaction((txnId: string, events: RawMatrixEvent[]) => {
      const seen = this.db.prepare("SELECT 1 FROM appservice_transactions WHERE txn_id = ?").get(txnId);
      if (seen) {
        return { inserted: 0, duplicate: true };
      }

      let inserted = 0;
      for (const event of events) {
        if (this.insertEvent(event)) {
          inserted += 1;
        }
      }

      this.db
        .prepare("INSERT INTO appservice_transactions (txn_id, processed_at) VALUES (?, ?)")
        .run(txnId, Date.now());

      return { inserted, duplicate: false };
    });
  }

  close(): void {
    this.db.close();
  }

  async processTransaction(txnId: string, events: RawMatrixEvent[]): Promise<{ inserted: number; duplicate: boolean }> {
    return this.processTransactionSync(txnId, events);
  }

  async listRooms(): Promise<RoomSummary[]> {
    return this.db
      .prepare(
        `SELECT room_id, name, canonical_alias, avatar_url, last_event_ts
         FROM rooms
         ORDER BY COALESCE(last_event_ts, 0) DESC, room_id ASC`
      )
      .all() as RoomSummary[];
  }

  async listRoomEvents(roomId: string, options: { cursor: EventCursor | null; limit: number }): Promise<EventPage> {
    const cursor = options.cursor;
    const rows = (cursor
      ? this.db
          .prepare(
            `SELECT event_id, room_id, origin_server_ts, raw_json
             FROM matrix_events
             WHERE room_id = ?
               AND (origin_server_ts > ? OR (origin_server_ts = ? AND event_id > ?))
             ORDER BY origin_server_ts ASC, event_id ASC
             LIMIT ?`
          )
          .all(roomId, cursor.ts, cursor.ts, cursor.event_id, options.limit)
      : this.db
          .prepare(
            `SELECT event_id, room_id, origin_server_ts, raw_json
             FROM matrix_events
             WHERE room_id = ?
             ORDER BY origin_server_ts ASC, event_id ASC
             LIMIT ?`
          )
          .all(roomId, options.limit)) as EventRow[];

    const events = rows.map((row) => JSON.parse(row.raw_json) as RawMatrixEvent);
    const last = rows.at(-1);

    return {
      room_id: roomId,
      events,
      next: last && rows.length === options.limit ? encodeCursor({ ts: last.origin_server_ts, event_id: last.event_id }) : null
    };
  }

  async getRoomEvent(roomId: string, eventId: string): Promise<RawMatrixEvent | null> {
    const row = this.db
      .prepare("SELECT raw_json FROM matrix_events WHERE room_id = ? AND event_id = ?")
      .get(roomId, eventId) as { raw_json: string } | undefined;

    return row ? (JSON.parse(row.raw_json) as RawMatrixEvent) : null;
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS appservice_transactions (
        txn_id TEXT PRIMARY KEY,
        processed_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS rooms (
        room_id TEXT PRIMARY KEY,
        name TEXT,
        canonical_alias TEXT,
        avatar_url TEXT,
        last_event_ts INTEGER
      );

      CREATE TABLE IF NOT EXISTS matrix_events (
        event_id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        type TEXT,
        sender TEXT,
        origin_server_ts INTEGER NOT NULL,
        state_key TEXT,
        raw_json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_matrix_events_room_ts
        ON matrix_events (room_id, origin_server_ts, event_id);

      CREATE INDEX IF NOT EXISTS idx_matrix_events_type
        ON matrix_events (type);
    `);
  }

  private insertEvent(event: RawMatrixEvent): boolean {
    const eventId = eventString(event.event_id);
    const roomId = eventString(event.room_id);
    if (!eventId || !roomId) {
      return false;
    }

    const type = eventString(event.type);
    const sender = eventString(event.sender);
    const stateKey = eventString(event.state_key);
    const ts = eventNumber(event.origin_server_ts);
    const rawJson = JSON.stringify(event);

    const result = this.db
      .prepare(
        `INSERT OR IGNORE INTO matrix_events
         (event_id, room_id, type, sender, origin_server_ts, state_key, raw_json)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .run(eventId, roomId, type, sender, ts, stateKey, rawJson);

    this.upsertRoom(event, roomId, ts);
    return result.changes > 0;
  }

  private upsertRoom(event: RawMatrixEvent, roomId: string, ts: number): void {
    this.db
      .prepare(
        `INSERT INTO rooms (room_id, last_event_ts)
         VALUES (?, ?)
         ON CONFLICT(room_id) DO UPDATE SET
           last_event_ts = CASE
             WHEN excluded.last_event_ts > COALESCE(rooms.last_event_ts, 0)
             THEN excluded.last_event_ts
             ELSE rooms.last_event_ts
           END`
      )
      .run(roomId, ts);

    const content = getStateContent(event);
    if (event.type === "m.room.name" && event.state_key === "") {
      this.db.prepare("UPDATE rooms SET name = ? WHERE room_id = ?").run(eventString(content.name), roomId);
    }
    if (event.type === "m.room.canonical_alias" && event.state_key === "") {
      this.db.prepare("UPDATE rooms SET canonical_alias = ? WHERE room_id = ?").run(eventString(content.alias), roomId);
    }
    if (event.type === "m.room.avatar" && event.state_key === "") {
      this.db.prepare("UPDATE rooms SET avatar_url = ? WHERE room_id = ?").run(eventString(content.url), roomId);
    }
  }
}

export { decodeCursor };

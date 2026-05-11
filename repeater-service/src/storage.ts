import type { EventCursor, EventPage, RawMatrixEvent, RoomSummary } from "./types.js";

export type StorageProvider = {
  close(): void;
  processTransaction(txnId: string, events: RawMatrixEvent[]): Promise<{ inserted: number; duplicate: boolean }>;
  listRooms(): Promise<RoomSummary[]>;
  listRoomEvents(roomId: string, options: { cursor: EventCursor | null; limit: number }): Promise<EventPage>;
  getRoomEvent(roomId: string, eventId: string): Promise<RawMatrixEvent | null>;
};

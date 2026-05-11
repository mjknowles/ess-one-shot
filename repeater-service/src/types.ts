export type RawMatrixEvent = Record<string, unknown> & {
  event_id?: string;
  room_id?: string;
  type?: string;
  sender?: string;
  origin_server_ts?: number;
  state_key?: string;
  content?: Record<string, unknown>;
};

export type AppserviceTransaction = {
  events?: RawMatrixEvent[];
  ephemeral?: RawMatrixEvent[];
};

export type RoomSummary = {
  room_id: string;
  name: string | null;
  canonical_alias: string | null;
  avatar_url: string | null;
  last_event_ts: number | null;
};

export type EventPage = {
  room_id: string;
  events: RawMatrixEvent[];
  next: string | null;
};

export type StoredEvent = {
  event: RawMatrixEvent;
  event_id: string;
  room_id: string;
  origin_server_ts: number;
};

export type EventCursor = {
  ts: number;
  event_id: string;
};

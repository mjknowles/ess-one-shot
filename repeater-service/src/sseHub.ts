import type { ServerResponse } from "node:http";
import type { RawMatrixEvent } from "./types.js";

type Client = {
  roomId: string;
  response: ServerResponse;
};

export class SseHub {
  private readonly clients = new Set<Client>();

  subscribe(roomId: string, response: ServerResponse): void {
    const client = { roomId, response };
    this.clients.add(client);

    response.writeHead(200, {
      "content-type": "text/event-stream",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no"
    });
    response.write(": connected\n\n");

    response.on("close", () => {
      this.clients.delete(client);
    });
  }

  publish(event: RawMatrixEvent): void {
    if (typeof event.room_id !== "string") return;
    const payload = `event: event\ndata: ${JSON.stringify(event)}\n\n`;

    for (const client of this.clients) {
      if (client.roomId === event.room_id) {
        client.response.write(payload);
      }
    }
  }
}

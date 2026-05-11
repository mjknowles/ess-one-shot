import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { AddressInfo } from "node:net";
import type { Config } from "./config.js";
import { createHttpServer } from "./http.js";
import { SqliteStorageProvider } from "./sqliteStorage.js";

const config: Config = {
  host: "127.0.0.1",
  port: 0,
  homeserverUrl: "http://synapse:8008",
  appserviceId: "repeater",
  appserviceUrl: "http://repeater-service:29330",
  asToken: "as-token",
  hsToken: "hs-token",
  senderLocalpart: "repeater",
  serverName: "ess.localhost",
  storageProvider: "sqlite",
  sqlitePath: ":memory:",
  receiveLogLevel: "off"
};

describe("raw event API", () => {
  const storage = new SqliteStorageProvider(":memory:");
  const server = createHttpServer(config, storage);
  let baseUrl = "";

  before(async () => {
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  after(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    storage.close();
  });

  it("rejects appservice transactions without the homeserver token", async () => {
    const response = await fetch(`${baseUrl}/_matrix/app/v1/transactions/unauthorized`, {
      method: "PUT",
      body: JSON.stringify({ events: [] })
    });

    assert.equal(response.status, 401);
  });

  it("stores and returns raw Matrix events without mutation", async () => {
    const event = {
      type: "m.room.message",
      room_id: "!room:ess.localhost",
      event_id: "$event1",
      sender: "@alice:ess.localhost",
      origin_server_ts: 1000,
      content: {
        msgtype: "m.text",
        body: "hello",
        "m.relates_to": {
          rel_type: "m.annotation",
          event_id: "$target",
          key: "👍"
        }
      },
      unsigned: {
        age: 12
      }
    };

    const ingest = await fetch(`${baseUrl}/_matrix/app/v1/transactions/txn1?access_token=hs-token`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ events: [event] })
    });
    assert.equal(ingest.status, 200);

    const byId = await fetch(`${baseUrl}/rooms/${encodeURIComponent(event.room_id)}/events/${encodeURIComponent(event.event_id)}`);
    assert.equal(byId.status, 200);
    assert.deepEqual(await byId.json(), event);

    const page = await fetch(`${baseUrl}/rooms/${encodeURIComponent(event.room_id)}/events?limit=10`);
    assert.equal(page.status, 200);
    assert.deepEqual(await page.json(), { room_id: event.room_id, events: [event], next: null });
  });

  it("does not duplicate events for duplicate transaction IDs", async () => {
    const event = {
      type: "m.room.message",
      room_id: "!room:ess.localhost",
      event_id: "$event2",
      sender: "@alice:ess.localhost",
      origin_server_ts: 2000,
      content: { msgtype: "m.text", body: "first" }
    };

    for (let i = 0; i < 2; i += 1) {
      const response = await fetch(`${baseUrl}/_matrix/app/v1/transactions/txn2`, {
        method: "PUT",
        headers: {
          authorization: "Bearer hs-token",
          "content-type": "application/json"
        },
        body: JSON.stringify({ events: [event] })
      });
      assert.equal(response.status, 200);
    }

    const page = await fetch(`${baseUrl}/rooms/${encodeURIComponent(event.room_id)}/events?limit=100`);
    const body = (await page.json()) as { events: Array<{ event_id: string }> };
    assert.equal(body.events.filter((stored) => stored.event_id === event.event_id).length, 1);
  });
});

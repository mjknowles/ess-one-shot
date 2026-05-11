import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Config } from "./config.js";
import { registrationYaml } from "./registration.js";

describe("registrationYaml", () => {
  it("registers a broad non-exclusive room namespace", () => {
    const config: Config = {
      host: "0.0.0.0",
      port: 29330,
      homeserverUrl: "http://synapse:8008",
      appserviceId: "repeater",
      appserviceUrl: "http://repeater-service:29330",
      asToken: "as",
      hsToken: "hs",
      senderLocalpart: "repeater",
      serverName: "ess.localhost",
      storageProvider: "sqlite",
      sqlitePath: ":memory:"
    };

    const yaml = registrationYaml(config);
    assert.match(yaml, /rooms:\n    - regex: '\.\*'\n      exclusive: false/);
    assert.match(yaml, /sender_localpart: repeater/);
  });
});

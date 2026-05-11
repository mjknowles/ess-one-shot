import { randomBytes } from "node:crypto";

export type Config = {
  host: string;
  port: number;
  homeserverUrl: string;
  appserviceId: string;
  appserviceUrl: string;
  asToken: string;
  hsToken: string;
  senderLocalpart: string;
  serverName: string;
  storageProvider: "sqlite";
  sqlitePath: string;
};

function intFromEnv(name: string, fallback: number): number {
  const value = process.env[name];
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) {
    throw new Error(`${name} must be an integer`);
  }
  return parsed;
}

function token(name: string): string {
  return process.env[name] ?? `dev-${name.toLowerCase()}-${randomBytes(16).toString("hex")}`;
}

export function loadConfig(): Config {
  const storageProvider = process.env.STORAGE_PROVIDER ?? "sqlite";
  if (storageProvider !== "sqlite") {
    throw new Error(`Unsupported STORAGE_PROVIDER '${storageProvider}'`);
  }

  return {
    host: process.env.HOST ?? "0.0.0.0",
    port: intFromEnv("PORT", 29330),
    homeserverUrl: process.env.HOMESERVER_URL ?? "http://ess-synapse:8008",
    appserviceId: process.env.APPSERVICE_ID ?? "repeater",
    appserviceUrl: process.env.APPSERVICE_URL ?? "http://repeater-service:29330",
    asToken: token("AS_TOKEN"),
    hsToken: token("HS_TOKEN"),
    senderLocalpart: process.env.SENDER_LOCALPART ?? "repeater",
    serverName: process.env.SERVER_NAME ?? "ess.localhost",
    storageProvider,
    sqlitePath: process.env.SQLITE_PATH ?? "/data/repeater.db"
  };
}

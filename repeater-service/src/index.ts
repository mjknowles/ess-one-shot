import { loadConfig } from "./config.js";
import { createHttpServer } from "./http.js";
import { SqliteStorageProvider } from "./sqliteStorage.js";

const config = loadConfig();
const storage = new SqliteStorageProvider(config.sqlitePath);
const server = createHttpServer(config, storage);

server.listen(config.port, config.host, () => {
  console.log(`repeater-service listening on ${config.host}:${config.port}`);
});

function shutdown(): void {
  server.close(() => {
    storage.close();
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

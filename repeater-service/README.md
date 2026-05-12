# Repeater Service

A minimal Matrix application service that records raw room events and exposes them through a read-only API.

## Development

```sh
npm install
npm run build
npm test
npm run dev
```

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `29330` | HTTP listen port. |
| `HOST` | `0.0.0.0` | HTTP listen host. |
| `HOMESERVER_URL` | `http://ess-synapse:8008` | Homeserver URL used in generated config/metadata. |
| `APPSERVICE_ID` | `repeater` | Matrix appservice ID. |
| `APPSERVICE_URL` | `http://repeater-service:29330` | URL Synapse uses to reach this appservice. |
| `AS_TOKEN` | generated dev token | Appservice token. |
| `HS_TOKEN` | generated dev token | Homeserver token accepted by appservice callbacks. |
| `SENDER_LOCALPART` | `repeater` | Appservice sender localpart. |
| `SERVER_NAME` | `ess.localhost` | Local Matrix server name used in generated registration. |
| `STORAGE_PROVIDER` | `sqlite` | Storage provider. Only `sqlite` is implemented initially. |
| `SQLITE_PATH` | `/data/repeater.db` | SQLite database path. |
| `RECEIVE_LOG_LEVEL` | `summary` | Receive logging level: `off`, `summary`, or `json`. |

## API

- `GET /healthz`
- `GET /rooms`
- `GET /rooms/:roomId/events?from=&limit=`
- `GET /rooms/:roomId/events/:eventId`
- `GET /rooms/:roomId/stream`
- `GET /registration.yaml`

Room events are returned as raw Matrix event JSON. The service does not normalize Matrix event content.

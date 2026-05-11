import type { Config } from "./config.js";

export function registrationYaml(config: Config): string {
  return [
    `id: ${config.appserviceId}`,
    `url: ${config.appserviceUrl}`,
    `as_token: ${config.asToken}`,
    `hs_token: ${config.hsToken}`,
    `sender_localpart: ${config.senderLocalpart}`,
    "rate_limited: false",
    "namespaces:",
    "  users: []",
    "  aliases: []",
    "  rooms:",
    "    - regex: '.*'",
    "      exclusive: false",
    ""
  ].join("\n");
}

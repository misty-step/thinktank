import path from "node:path";

import { isTopLevelTelemetryEnabled } from "../shared/depth-telemetry";

export const ENABLE_NESTED_WEB_SEARCH_LOG_ENV = "PI_WEB_SEARCH_ENABLE_NESTED_LOG";
export const ENABLE_NESTED_WEB_SEARCH_WARN_ENV = "PI_WEB_SEARCH_ENABLE_NESTED_WARN";

export function resolveWebSearchLogPath(
  configDir: string,
  depth: number,
  env: Record<string, string | undefined> = process.env,
): string | undefined {
  const telemetryEnabled =
    depth <= 0 ||
    isTopLevelTelemetryEnabled(ENABLE_NESTED_WEB_SEARCH_LOG_ENV, {
      ...env,
      PI_ORCH_DEPTH: String(depth),
    });
  if (!telemetryEnabled) {
    return undefined;
  }
  return path.join(configDir, "logs", "web-search.ndjson");
}

export function currentOrchestrationDepth(
  env: Record<string, string | undefined> = process.env,
): number {
  const raw = Number(env.PI_ORCH_DEPTH ?? 0);
  if (!Number.isFinite(raw) || raw < 0) {
    return 0;
  }
  return Math.floor(raw);
}

export function isTruthyEnvFlag(
  value: string | undefined,
): boolean {
  if (typeof value !== "string") {
    return false;
  }
  return ["1", "true", "yes", "on"].includes(value.trim().toLowerCase());
}

export function isTopLevelTelemetryEnabled(
  nestedEnableFlagName: string,
  env: Record<string, string | undefined> = process.env,
): boolean {
  const depth = currentOrchestrationDepth(env);
  if (depth <= 0) {
    return true;
  }
  return isTruthyEnvFlag(env[nestedEnableFlagName]);
}

import { appendFile, mkdir, rename, stat, unlink } from "node:fs/promises";
import path from "node:path";

export interface LogRotationOptions {
  maxBytes: number;
  maxBackups: number;
  checkIntervalMs?: number;
}

interface RotationState {
  lastCheckAt: number;
}

const DEFAULT_CHECK_INTERVAL_MS = 15_000;
const MIN_CHECK_INTERVAL_MS = 0;
const MAX_CHECK_INTERVAL_MS = 10 * 60 * 1000;
const MIN_MAX_BYTES = 64 * 1024;
const MAX_MAX_BYTES = 1024 * 1024 * 1024;
const MIN_MAX_BACKUPS = 1;
const MAX_MAX_BACKUPS = 20;

const rotationStateByPath = new Map<string, RotationState>();

export async function appendLineWithRotation(
  logPath: string,
  line: string,
  options: LogRotationOptions,
): Promise<void> {
  const normalized = normalizeOptions(options);
  await mkdir(path.dirname(logPath), { recursive: true });

  const state = rotationStateByPath.get(logPath) ?? { lastCheckAt: 0 };
  rotationStateByPath.set(logPath, state);

  const now = Date.now();
  if (normalized.checkIntervalMs === 0 || now - state.lastCheckAt >= normalized.checkIntervalMs) {
    state.lastCheckAt = now;
    await rotateLogIfNeeded(logPath, normalized.maxBytes, normalized.maxBackups);
  }

  const content = line.endsWith("\n") ? line : `${line}\n`;
  await appendFile(logPath, content, "utf8");
}

export async function rotateLogIfNeeded(
  logPath: string,
  maxBytes: number,
  maxBackups: number,
): Promise<boolean> {
  let fileSize = 0;
  try {
    const info = await stat(logPath);
    fileSize = info.size;
  } catch {
    return false;
  }

  if (fileSize < maxBytes) {
    return false;
  }

  for (let index = maxBackups; index >= 1; index -= 1) {
    const source = index === 1 ? logPath : `${logPath}.${index - 1}`;
    const destination = `${logPath}.${index}`;

    if (index === maxBackups) {
      try {
        await unlink(destination);
      } catch {
        // no-op
      }
    }

    try {
      await rename(source, destination);
    } catch (error) {
      if (!isMissingFileError(error)) {
        throw error;
      }
    }
  }

  return true;
}

function normalizeOptions(options: LogRotationOptions): Required<LogRotationOptions> {
  return {
    maxBytes: clampInt(options.maxBytes, MIN_MAX_BYTES, MAX_MAX_BYTES),
    maxBackups: clampInt(options.maxBackups, MIN_MAX_BACKUPS, MAX_MAX_BACKUPS),
    checkIntervalMs: clampInt(
      options.checkIntervalMs ?? DEFAULT_CHECK_INTERVAL_MS,
      MIN_CHECK_INTERVAL_MS,
      MAX_CHECK_INTERVAL_MS,
    ),
  };
}

function clampInt(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.max(min, Math.min(max, Math.floor(value)));
}

function isMissingFileError(error: unknown): boolean {
  if (!(error instanceof Error)) {
    return false;
  }
  return /ENOENT/i.test(error.message);
}

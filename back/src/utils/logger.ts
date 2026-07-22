import { env } from "../config/env";

type LogLevel = "debug" | "info" | "warn" | "error";

const logLevelPriority: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

type LogContext = Record<string, unknown>;

function shouldLog(level: LogLevel): boolean {
  return logLevelPriority[level] >= logLevelPriority[env.LOG_LEVEL];
}

function serializeError(error: unknown) {
  if (!(error instanceof Error)) {
    return error;
  }

  return {
    name: error.name,
    message: error.message,
    stack: env.NODE_ENV === "production" ? undefined : error.stack,
  };
}

export function log(level: LogLevel, event: string, context: LogContext = {}): void {
  if (!shouldLog(level)) {
    return;
  }

  const payload = {
    timestamp: new Date().toISOString(),
    level,
    event,
    service: "corporate-app-store-api",
    environment: env.NODE_ENV,
    ...context,
  };

  const serializedPayload = JSON.stringify(payload, (_key, value) => {
    if (typeof value === "bigint") {
      return value.toString();
    }

    if (value instanceof Error) {
      return serializeError(value);
    }

    return value;
  });

  if (level === "error") {
    console.error(serializedPayload);
    return;
  }

  if (level === "warn") {
    console.warn(serializedPayload);
    return;
  }

  console.log(serializedPayload);
}

export function logInfo(event: string, context?: LogContext): void {
  log("info", event, context);
}

export function logWarn(event: string, context?: LogContext): void {
  log("warn", event, context);
}

export function logError(event: string, context?: LogContext): void {
  log("error", event, context);
}

export function logDebug(event: string, context?: LogContext): void {
  log("debug", event, context);
}

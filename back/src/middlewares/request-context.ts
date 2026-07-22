import { randomUUID } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { logInfo } from "../utils/logger";

export function requestContext(req: Request, res: Response, next: NextFunction): void {
  const requestIdHeader = req.headers["x-request-id"];
  const requestId =
    (typeof requestIdHeader === "string" && requestIdHeader.trim()) ||
    (Array.isArray(requestIdHeader) && requestIdHeader[0]?.trim()) ||
    randomUUID();
  const startedAt = Date.now();

  req.requestId = requestId;
  res.setHeader("x-request-id", requestId);

  res.on("finish", () => {
    logInfo("http.request", {
      requestId,
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: Date.now() - startedAt,
      ip: resolveClientIp(req),
      userId: req.user?.userId ?? null,
      userAgent: req.get("user-agent") ?? null,
    });
  });

  next();
}

function resolveClientIp(req: Request): string {
  return req.ip ?? req.socket.remoteAddress ?? "unknown";
}

import { Prisma } from "@prisma/client";
import type { NextFunction, Request, Response } from "express";
import { ZodError } from "zod";
import { ApiError } from "../utils/api-error";
import { logError, logWarn } from "../utils/logger";

export function notFoundHandler(_req: Request, _res: Response, next: NextFunction): void {
  next(new ApiError(404, "Route not found"));
}

export function errorHandler(
  error: unknown,
  req: Request,
  res: Response,
  _next: NextFunction,
): void {
  if (error instanceof ApiError) {
    logWarn("http.error", {
      requestId: req.requestId ?? null,
      path: req.originalUrl,
      method: req.method,
      statusCode: error.statusCode,
      message: error.message,
      details: error.details ?? null,
      userId: req.user?.userId ?? null,
    });

    res.status(error.statusCode).json({
      message: error.message,
      details: error.details,
    });
    return;
  }

  if (error instanceof ZodError) {
    logWarn("http.validation_failed", {
      requestId: req.requestId ?? null,
      path: req.originalUrl,
      method: req.method,
      statusCode: 400,
      details: error.flatten(),
      userId: req.user?.userId ?? null,
    });

    res.status(400).json({
      message: "Validation failed",
      details: error.flatten(),
    });
    return;
  }

  if (error instanceof Prisma.PrismaClientKnownRequestError) {
    if (error.code === "P2002") {
      logWarn("db.unique_constraint", {
        requestId: req.requestId ?? null,
        path: req.originalUrl,
        method: req.method,
        statusCode: 409,
        code: error.code,
        details: error.meta ?? null,
        userId: req.user?.userId ?? null,
      });

      res.status(409).json({
        message: "A unique constraint was violated",
        details: error.meta,
      });
      return;
    }

    logWarn("db.operation_failed", {
      requestId: req.requestId ?? null,
      path: req.originalUrl,
      method: req.method,
      statusCode: 400,
      code: error.code,
      details: error.meta ?? null,
      userId: req.user?.userId ?? null,
    });

    res.status(400).json({
      message: "Database operation failed",
      details: error.meta,
    });
    return;
  }

  logError("http.unhandled_error", {
    requestId: req.requestId ?? null,
    path: req.originalUrl,
    method: req.method,
    statusCode: 500,
    error:
      error instanceof Error
        ? {
            name: error.name,
            message: error.message,
            stack: error.stack ?? null,
          }
        : {
            value: String(error),
          },
    userId: req.user?.userId ?? null,
  });

  res.status(500).json({
    message: "Internal server error",
  });
}

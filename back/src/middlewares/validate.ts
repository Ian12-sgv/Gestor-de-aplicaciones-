import type { NextFunction, Request, RequestHandler, Response } from "express";
import type { ZodTypeAny } from "zod";
import { ApiError } from "../utils/api-error";

type RequestSource = "body" | "query" | "params";

export function validate(schema: ZodTypeAny, source: RequestSource = "body"): RequestHandler {
  return (req: Request, _res: Response, next: NextFunction) => {
    const result = schema.safeParse(req[source]);

    if (!result.success) {
      next(new ApiError(400, "Validation failed", result.error.flatten()));
      return;
    }

    (req as Record<RequestSource, unknown>)[source] = result.data;
    next();
  };
}

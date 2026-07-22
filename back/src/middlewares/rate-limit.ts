import type { NextFunction, Request, Response } from "express";
import { ApiError } from "../utils/api-error";
import { logWarn } from "../utils/logger";

type RateLimitOptions = {
  name: string;
  windowMs: number;
  maxRequests: number;
  maxBuckets: number;
  keyGenerator?: (req: Request) => string;
};

type RateLimitBucket = {
  count: number;
  lastSeenAt: number;
  resetAt: number;
};

const rateLimitBuckets = new Map<string, RateLimitBucket>();

export function createRateLimiter(options: RateLimitOptions) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const now = Date.now();
    const bucketKey = `${options.name}:${(options.keyGenerator ?? resolveClientIp)(req)}`;
    const existingBucket = rateLimitBuckets.get(bucketKey);

    pruneExpiredBuckets(now);

    const bucket =
      !existingBucket || existingBucket.resetAt <= now
        ? {
            count: 0,
            lastSeenAt: now,
            resetAt: now + options.windowMs,
          }
        : existingBucket;

    bucket.count += 1;
    bucket.lastSeenAt = now;
    rateLimitBuckets.set(bucketKey, bucket);
    enforceBucketLimit(options.maxBuckets);

    const remainingRequests = Math.max(options.maxRequests - bucket.count, 0);
    const retryAfterSeconds = Math.max(Math.ceil((bucket.resetAt - now) / 1000), 1);

    res.setHeader("x-ratelimit-limit", String(options.maxRequests));
    res.setHeader("x-ratelimit-remaining", String(remainingRequests));
    res.setHeader("x-ratelimit-reset", String(Math.ceil(bucket.resetAt / 1000)));

    if (bucket.count > options.maxRequests) {
      res.setHeader("retry-after", String(retryAfterSeconds));

      logWarn("rate_limit.exceeded", {
        requestId: req.requestId ?? null,
        limiter: options.name,
        ip: resolveClientIp(req),
        path: req.originalUrl,
        key: bucketKey,
        retryAfterSeconds,
      });

      next(
        new ApiError(429, "Too many requests. Please wait and try again.", {
          limiter: options.name,
          retryAfterSeconds,
        }),
      );
      return;
    }

    next();
  };
}

export function resolveClientIp(req: Request): string {
  return req.ip ?? req.socket.remoteAddress ?? "unknown";
}

export function resolveAuthRateLimitKey(req: Request): string {
  const identifier =
    typeof req.body?.identifier === "string" && req.body.identifier.trim()
      ? req.body.identifier.trim().toLowerCase()
      : "unknown";

  return `${resolveClientIp(req)}:${identifier}`;
}

function pruneExpiredBuckets(now: number): void {
  for (const [bucketKey, bucket] of rateLimitBuckets.entries()) {
    if (bucket.resetAt <= now) {
      rateLimitBuckets.delete(bucketKey);
    }
  }
}

function enforceBucketLimit(maxBuckets: number): void {
  if (rateLimitBuckets.size <= maxBuckets) {
    return;
  }

  const bucketsByAge = [...rateLimitBuckets.entries()].sort(
    (left, right) => left[1].lastSeenAt - right[1].lastSeenAt,
  );
  const deleteCount = rateLimitBuckets.size - maxBuckets;

  for (const [bucketKey] of bucketsByAge.slice(0, deleteCount)) {
    rateLimitBuckets.delete(bucketKey);
  }
}

import { constants as fsConstants } from "node:fs";
import { access, stat } from "node:fs/promises";
import { Router } from "express";
import { env } from "../../config/env";
import { prisma } from "../../config/prisma";
import { asyncHandler } from "../../utils/async-handler";

const router = Router();

async function checkDatabase() {
  const startedAt = Date.now();

  try {
    await prisma.$queryRaw`SELECT 1`;

    return {
      status: "ok",
      latencyMs: Date.now() - startedAt,
    };
  } catch (error) {
    return {
      status: "error",
      latencyMs: Date.now() - startedAt,
      error: error instanceof Error ? error.message : "Unknown database error",
    };
  }
}

async function checkApkStorage() {
  try {
    const storageStats = await stat(env.APK_STORAGE_DIR);
    const isDirectory = storageStats.isDirectory();

    if (!isDirectory) {
      return {
        status: "error",
        path: env.APK_STORAGE_DIR,
        isDirectory: false,
        writable: false,
        error: "APK storage path exists but is not a directory",
      };
    }

    await access(env.APK_STORAGE_DIR, fsConstants.R_OK | fsConstants.W_OK);

    return {
      status: "ok",
      path: env.APK_STORAGE_DIR,
      isDirectory: true,
      writable: true,
    };
  } catch (error) {
    return {
      status: "error",
      path: env.APK_STORAGE_DIR,
      isDirectory: false,
      writable: false,
      error: error instanceof Error ? error.message : "Unknown storage error",
    };
  }
}

router.get("/", asyncHandler(async (_req, res) => {
  const [database, apkStorage] = await Promise.all([
    checkDatabase(),
    checkApkStorage(),
  ]);
  const status = database.status === "ok" && apkStorage.status === "ok" ? "ok" : "degraded";

  res.status(status === "ok" ? 200 : 503).json({
    status,
    timestamp: new Date().toISOString(),
    service: "corporate-app-store-api",
    environment: env.NODE_ENV,
    configSource: env.CONFIG_SOURCE,
    uptimeSeconds: Math.round(process.uptime()),
    checks: {
      database,
      apkStorage,
    },
    session: {
      accessTokenTtl: env.JWT_EXPIRES_IN,
      refreshTokenTtlDays: env.REFRESH_TOKEN_TTL_DAYS,
      revocationStrategy: "Immediate revocation via sessionVersion, user status and refresh token rotation",
    },
    rateLimit: {
      generalWindowMs: env.RATE_LIMIT_WINDOW_MS,
      generalMaxRequests: env.RATE_LIMIT_MAX_REQUESTS,
      maxBuckets: env.RATE_LIMIT_MAX_BUCKETS,
      authWindowMs: env.AUTH_RATE_LIMIT_WINDOW_MS,
      authMaxRequests: env.AUTH_RATE_LIMIT_MAX_REQUESTS,
    },
  });
}));

export const healthRoutes = router;

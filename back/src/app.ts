import cors from "cors";
import express from "express";
import helmet from "helmet";
import { env } from "./config/env";
import { authenticate, requirePasswordReady } from "./middlewares/authenticate";
import { errorHandler, notFoundHandler } from "./middlewares/error-handler";
import { createRateLimiter } from "./middlewares/rate-limit";
import { requestContext } from "./middlewares/request-context";
import { adminRoutes } from "./modules/admin/admin.routes";
import { appsRoutes } from "./modules/apps/apps.routes";
import { authRoutes } from "./modules/auth/auth.routes";
import { devicesRoutes } from "./modules/devices/devices.routes";
import { healthRoutes } from "./modules/health/health.routes";

const app = express();
const apiRateLimiter = createRateLimiter({
  name: "api.general",
  windowMs: env.RATE_LIMIT_WINDOW_MS,
  maxRequests: env.RATE_LIMIT_MAX_REQUESTS,
  maxBuckets: env.RATE_LIMIT_MAX_BUCKETS,
});

app.disable("x-powered-by");
app.set("trust proxy", env.TRUST_PROXY === "false" ? false : env.TRUST_PROXY);
app.use(helmet());
app.use(
  cors({
    origin:
      env.CORS_ORIGIN === "*"
        ? true
        : env.CORS_ORIGIN.split(",").map((origin) => origin.trim()),
    credentials: true,
  }),
);
app.use(requestContext);
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true }));

app.get("/", (_req, res) => {
  res.status(200).json({
    service: "corporate-app-store-api",
    status: "ok",
  });
});

app.use(`${env.API_PREFIX}/health`, healthRoutes);
app.use(env.API_PREFIX, apiRateLimiter);
app.use(`${env.API_PREFIX}/auth`, authRoutes);
app.use(`${env.API_PREFIX}/apps`, authenticate, requirePasswordReady, appsRoutes);
app.use(`${env.API_PREFIX}/devices`, authenticate, requirePasswordReady, devicesRoutes);
app.use(`${env.API_PREFIX}/admin`, authenticate, requirePasswordReady, adminRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

export { app };

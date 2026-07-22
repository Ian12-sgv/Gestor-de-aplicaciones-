import { Router } from "express";
import { authenticate } from "../../middlewares/authenticate";
import {
  createRateLimiter,
  resolveAuthRateLimitKey,
  resolveClientIp,
} from "../../middlewares/rate-limit";
import { env } from "../../config/env";
import { validate } from "../../middlewares/validate";
import {
  changePasswordController,
  loginController,
  logoutController,
  meController,
  refreshController,
} from "./auth.controller";
import {
  changePasswordSchema,
  loginSchema,
  logoutSchema,
  refreshSessionSchema,
} from "./auth.schemas";

const router = Router();
const authRateLimiter = createRateLimiter({
  name: "auth.login",
  windowMs: env.AUTH_RATE_LIMIT_WINDOW_MS,
  maxRequests: env.AUTH_RATE_LIMIT_MAX_REQUESTS,
  maxBuckets: env.RATE_LIMIT_MAX_BUCKETS,
  keyGenerator: resolveAuthRateLimitKey,
});
const refreshRateLimiter = createRateLimiter({
  name: "auth.refresh",
  windowMs: env.AUTH_RATE_LIMIT_WINDOW_MS,
  maxRequests: env.AUTH_RATE_LIMIT_MAX_REQUESTS,
  maxBuckets: env.RATE_LIMIT_MAX_BUCKETS,
  keyGenerator: resolveClientIp,
});

router.post("/login", authRateLimiter, validate(loginSchema), loginController);
router.post("/refresh", refreshRateLimiter, validate(refreshSessionSchema), refreshController);
router.post("/logout", validate(logoutSchema), logoutController);
router.post("/change-password", authenticate, validate(changePasswordSchema), changePasswordController);
router.get("/me", authenticate, meController);

export const authRoutes = router;

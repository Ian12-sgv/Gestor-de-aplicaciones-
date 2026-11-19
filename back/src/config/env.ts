import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import { z } from "zod";

function loadLocalEnvIfAllowed(): void {
  const nodeEnv = process.env.NODE_ENV ?? "development";
  const allowDotenvInProd = process.env.ALLOW_DOTENV_IN_PROD === "true";
  const shouldLoadLocalEnv = nodeEnv !== "production" || allowDotenvInProd;
  const envFilePath = path.resolve(process.cwd(), ".env");

  if (shouldLoadLocalEnv && fs.existsSync(envFilePath)) {
    dotenv.config({ path: envFilePath });
  }
}

loadLocalEnvIfAllowed();

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().positive().default(3000),
  API_PREFIX: z.string().default("/api"),
  CORS_ORIGIN: z.string().default("*"),
  TRUST_PROXY: z.string().default("loopback"),
  DATABASE_URL: z.string().min(1, "DATABASE_URL is required"),
  JWT_SECRET: z.string().min(32, "JWT_SECRET must contain at least 32 characters"),
  JWT_EXPIRES_IN: z.string().default("15m"),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  APK_STORAGE_DIR: z.string().default("./storage/apks"),
  // Optional: defaults to a "media" folder next to APK_STORAGE_DIR.
  MEDIA_STORAGE_DIR: z.string().trim().min(1).optional(),
  ADMIN_WEB_DIR: z.string().default("./admin-web"),
  APK_AUTO_IMPORT_ENABLED: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => value === "true"),
  APK_AUTO_IMPORT_POLL_INTERVAL_MS: z.coerce.number().int().positive().default(4_000),
  APK_AUTO_IMPORT_STABLE_MS: z.coerce.number().int().positive().default(6_000),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),
  RATE_LIMIT_MAX_REQUESTS: z.coerce.number().int().positive().default(240),
  RATE_LIMIT_MAX_BUCKETS: z.coerce.number().int().positive().default(10_000),
  AUTH_RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(900_000),
  AUTH_RATE_LIMIT_MAX_REQUESTS: z.coerce.number().int().positive().default(10),
  ALLOW_DOTENV_IN_PROD: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => value === "true"),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
});

const parsedEnv = envSchema.safeParse(process.env);

if (!parsedEnv.success) {
  console.error("Invalid environment variables", parsedEnv.error.flatten().fieldErrors);
  throw new Error("Environment validation failed");
}

const envData = parsedEnv.data;
const isUsingLocalDotenv =
  fs.existsSync(path.resolve(process.cwd(), ".env")) &&
  (envData.NODE_ENV !== "production" || envData.ALLOW_DOTENV_IN_PROD);
const resolvedApkStorageDir = path.resolve(process.cwd(), envData.APK_STORAGE_DIR);
const resolvedMediaStorageDir = envData.MEDIA_STORAGE_DIR
  ? path.resolve(process.cwd(), envData.MEDIA_STORAGE_DIR)
  : path.join(path.dirname(resolvedApkStorageDir), "media");
const resolvedAdminWebDir = path.resolve(process.cwd(), envData.ADMIN_WEB_DIR);

if (envData.NODE_ENV === "production") {
  validateProductionEnvironment(envData);
}

export const env = {
  ...envData,
  APK_STORAGE_DIR: resolvedApkStorageDir,
  MEDIA_STORAGE_DIR: resolvedMediaStorageDir,
  ADMIN_WEB_DIR: resolvedAdminWebDir,
  CONFIG_SOURCE: isUsingLocalDotenv ? "local-dotenv" : "runtime-environment",
};

function validateProductionEnvironment(data: z.infer<typeof envSchema>): void {
  const errors: string[] = [];

  if (data.JWT_SECRET.includes("replace-with-a-long-random-secret")) {
    errors.push("JWT_SECRET must be overridden by the runtime environment in production.");
  }

  if (data.CORS_ORIGIN.trim() === "*") {
    errors.push("CORS_ORIGIN must list explicit trusted origins in production.");
  }

  if (!data.API_PREFIX.startsWith("/")) {
    errors.push("API_PREFIX must start with '/' in production.");
  }

  if (!path.isAbsolute(data.APK_STORAGE_DIR)) {
    errors.push("APK_STORAGE_DIR must be an absolute private path in production.");
  }

  if (data.MEDIA_STORAGE_DIR && !path.isAbsolute(data.MEDIA_STORAGE_DIR)) {
    errors.push("MEDIA_STORAGE_DIR must be an absolute private path in production.");
  }

  if (isPublicBindHost(data.HOST)) {
    errors.push("HOST must bind to loopback in production; expose the app through Caddy.");
  }

  if (data.ALLOW_DOTENV_IN_PROD) {
    errors.push("ALLOW_DOTENV_IN_PROD must remain false in production.");
  }

  if (errors.length > 0) {
    throw new Error(`Production environment validation failed: ${errors.join(" ")}`);
  }
}

function isPublicBindHost(host: string): boolean {
  const normalizedHost = host.trim().toLowerCase();
  return normalizedHost === "0.0.0.0" || normalizedHost === "::" || normalizedHost === "";
}

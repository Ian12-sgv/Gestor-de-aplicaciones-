import { z } from "zod";
import { APP_STATUSES, ROLE_CODES } from "../../config/domain";

function parseBoolean(value: unknown): unknown {
  if (typeof value === "string") {
    if (value.toLowerCase() === "true") {
      return true;
    }

    if (value.toLowerCase() === "false") {
      return false;
    }
  }

  return value;
}

export const appParamsSchema = z.object({
  id: z.string().uuid(),
});

export const versionParamsSchema = z.object({
  id: z.string().uuid(),
});

export const userParamsSchema = z.object({
  id: z.string().uuid(),
});

export const appUserParamsSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().uuid(),
});

export const appRoleParamsSchema = z.object({
  id: z.string().uuid(),
  roleCode: z.enum(ROLE_CODES),
});

export const createAppSchema = z.object({
  packageName: z.string().trim().min(3).max(255),
  slug: z.string().trim().min(3).max(150).optional(),
  displayName: z.string().trim().min(2).max(150),
  shortDescription: z.string().trim().max(300).optional(),
  description: z.string().trim().max(4000).optional(),
  iconPath: z.string().trim().max(500).optional(),
  bannerPath: z.string().trim().max(500).optional(),
  category: z.string().trim().max(100).optional(),
  requiresExplicitAccess: z.preprocess(parseBoolean, z.boolean()).optional(),
  status: z.enum(APP_STATUSES).optional(),
});

export const updateAppSchema = z
  .object({
    slug: z.string().trim().min(3).max(150).optional(),
    displayName: z.string().trim().min(2).max(150).optional(),
    shortDescription: z.string().trim().max(300).nullable().optional(),
    description: z.string().trim().max(4000).nullable().optional(),
    category: z.string().trim().max(100).nullable().optional(),
    requiresExplicitAccess: z.preprocess(parseBoolean, z.boolean()).optional(),
  })
  .refine((input) => Object.keys(input).length > 0, "At least one field is required.");

const emptyStringToUndefined = (value: unknown) =>
  typeof value === "string" && value.trim() === "" ? undefined : value;

// versionName/versionCode are optional for uploads: they are read from the APK manifest.
export const createAppVersionSchema = z.object({
  versionName: z.preprocess(emptyStringToUndefined, z.string().trim().min(1).max(60).optional()),
  versionCode: z.preprocess(emptyStringToUndefined, z.coerce.number().int().positive().optional()),
  changelog: z.string().trim().max(4000).optional(),
  sha256: z
    .string()
    .trim()
    .regex(/^[a-fA-F0-9]{64}$/, "sha256 must be a 64-character hexadecimal string")
    .optional(),
  minSupportedVersionCode: z.coerce.number().int().positive().optional(),
  isMandatory: z.preprocess(parseBoolean, z.boolean()).optional(),
  apkRelativePath: z.string().trim().max(500).optional(),
});

export const updateAppStatusSchema = z.object({
  status: z.enum(APP_STATUSES),
});

export const updateVersionMandatorySchema = z.object({
  isMandatory: z.preprocess(parseBoolean, z.boolean()),
});

export const revokeUserAccessSchema = z.object({
  status: z.enum(["DISABLED"]).default("DISABLED"),
});

export const createUserSchema = z.object({
  email: z.string().trim().email().max(320),
  username: z.string().trim().min(3).max(100),
  password: z.string().min(8).max(128),
  firstName: z.string().trim().max(100).optional(),
  lastName: z.string().trim().max(100).optional(),
  status: z.enum(["ACTIVE", "DISABLED"]).default("ACTIVE"),
  roleCodes: z.array(z.enum(ROLE_CODES)).min(1),
});

export const upsertAppUserAccessSchema = z.object({
  canView: z.preprocess(parseBoolean, z.boolean()).default(true),
  canInstall: z.preprocess(parseBoolean, z.boolean()).default(true),
});

export const listInstallationLogsQuerySchema = z.object({
  appId: z.string().uuid().optional(),
  userId: z.string().uuid().optional(),
  deviceId: z.string().uuid().optional(),
  action: z.enum(["DOWNLOAD", "INSTALL", "UPDATE", "OPEN", "REMOVE"]).optional(),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

export type CreateAppInput = z.infer<typeof createAppSchema>;
export type CreateAppVersionInput = z.infer<typeof createAppVersionSchema>;
export type UpdateAppInput = z.infer<typeof updateAppSchema>;
export type UpdateAppStatusInput = z.infer<typeof updateAppStatusSchema>;
export type UpdateVersionMandatoryInput = z.infer<typeof updateVersionMandatorySchema>;
export type RevokeUserAccessInput = z.infer<typeof revokeUserAccessSchema>;
export type CreateUserInput = z.infer<typeof createUserSchema>;
export type UpsertAppUserAccessInput = z.infer<typeof upsertAppUserAccessSchema>;
export type ListInstallationLogsQuery = z.infer<typeof listInstallationLogsQuerySchema>;

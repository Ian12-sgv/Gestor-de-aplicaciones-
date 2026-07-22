import { z } from "zod";

export const appIdParamsSchema = z.object({
  id: z.string().uuid(),
});

export const appsListQuerySchema = z.object({
  deviceId: z.string().uuid().optional(),
});

export const appDetailQuerySchema = z.object({
  deviceId: z.string().uuid().optional(),
});

export const downloadQuerySchema = z.object({
  deviceId: z.string().uuid().optional(),
  versionCode: z.coerce.number().int().positive().optional(),
});


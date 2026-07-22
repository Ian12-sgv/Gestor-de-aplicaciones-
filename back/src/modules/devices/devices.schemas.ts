import { z } from "zod";
import {
  DEVICE_APP_STATUSES,
  DEVICE_STATUSES,
  INSTALLATION_ACTIONS,
  INSTALLATION_RESULT_STATUSES,
} from "../../config/domain";

export const registerDeviceSchema = z.object({
  deviceIdentifier: z.string().trim().min(3).max(191),
  name: z.string().trim().min(2).max(150),
  manufacturer: z.string().trim().max(120).optional(),
  model: z.string().trim().max(120).optional(),
  osVersion: z.string().trim().max(50).optional(),
  appVersionName: z.string().trim().max(60).optional(),
  pushToken: z.string().trim().max(255).optional(),
  status: z.enum(DEVICE_STATUSES).optional(),
});

export const reportInstallationSchema = z.object({
  deviceId: z.string().uuid(),
  appId: z.string().uuid(),
  appVersionId: z.string().uuid().optional(),
  installedVersionCode: z.number().int().positive().optional(),
  installedVersionName: z.string().trim().max(60).optional(),
  action: z.enum(INSTALLATION_ACTIONS),
  status: z.enum(INSTALLATION_RESULT_STATUSES),
  notes: z.string().trim().max(500).optional(),
  deviceAppStatus: z.enum(DEVICE_APP_STATUSES).optional(),
});

export type RegisterDeviceInput = z.infer<typeof registerDeviceSchema>;
export type ReportInstallationInput = z.infer<typeof reportInstallationSchema>;


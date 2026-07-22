import { hasPermission, PERMISSIONS } from "../../config/domain";
import { prisma } from "../../config/prisma";
import { ApiError } from "../../utils/api-error";
import type { AuthenticatedRequestUser } from "../auth/auth.types";
import type { RegisterDeviceInput, ReportInstallationInput } from "./devices.schemas";

function canManageDevice(user: AuthenticatedRequestUser, ownerUserId: string | null): boolean {
  return hasPermission(user.roles, PERMISSIONS.DEVICE_REPORT_ANY) || ownerUserId === user.userId;
}

export async function registerDevice(input: RegisterDeviceInput, user: AuthenticatedRequestUser) {
  const existingDevice = await prisma.device.findUnique({
    where: {
      deviceIdentifier: input.deviceIdentifier,
    },
  });

  if (existingDevice && existingDevice.userId && existingDevice.userId !== user.userId) {
    throw new ApiError(409, "Device identifier is already bound to another user");
  }

  const device = await prisma.device.upsert({
    where: {
      deviceIdentifier: input.deviceIdentifier,
    },
    create: {
      deviceIdentifier: input.deviceIdentifier,
      name: input.name,
      manufacturer: input.manufacturer,
      model: input.model,
      osVersion: input.osVersion,
      appVersionName: input.appVersionName,
      pushToken: input.pushToken,
      status: input.status ?? "ACTIVE",
      platform: "ANDROID",
      userId: user.userId,
      lastSeenAt: new Date(),
    },
    update: {
      name: input.name,
      manufacturer: input.manufacturer,
      model: input.model,
      osVersion: input.osVersion,
      appVersionName: input.appVersionName,
      pushToken: input.pushToken,
      status: input.status ?? existingDevice?.status ?? "ACTIVE",
      userId: user.userId,
      lastSeenAt: new Date(),
    },
  });

  return device;
}

export async function reportInstallation(
  input: ReportInstallationInput,
  user: AuthenticatedRequestUser,
) {
  const device = await prisma.device.findUnique({
    where: {
      id: input.deviceId,
    },
  });

  if (!device) {
    throw new ApiError(404, "Device not found");
  }

  if (!canManageDevice(user, device.userId ?? null)) {
    throw new ApiError(403, "You are not allowed to report for this device");
  }

  const app = await prisma.app.findUnique({
    where: {
      id: input.appId,
    },
    include: {
      versions: {
        orderBy: {
          versionCode: "desc",
        },
        take: 1,
      },
    },
  });

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  let version = null;

  if (input.appVersionId) {
    version = await prisma.appVersion.findUnique({
      where: {
        id: input.appVersionId,
      },
    });

    if (!version || version.appId !== app.id) {
      throw new ApiError(400, "The provided appVersionId does not belong to the application");
    }
  }

  const existingState = await prisma.deviceAppState.findUnique({
    where: {
      deviceId_appId: {
        deviceId: input.deviceId,
        appId: input.appId,
      },
    },
  });

  const resolvedVersionCode = input.installedVersionCode ?? version?.versionCode ?? null;
  const resolvedVersionName = input.installedVersionName ?? version?.versionName ?? null;
  const latestVersionCode = app.versions[0]?.versionCode ?? null;

  let nextStatus = input.deviceAppStatus ?? existingState?.status ?? "UNKNOWN";
  let installedVersionId = existingState?.installedVersionId ?? null;
  let installedVersionCode = existingState?.installedVersionCode ?? null;
  let installedVersionName = existingState?.installedVersionName ?? null;
  let lastOpenedAt = existingState?.lastOpenedAt ?? null;

  if (input.action === "REMOVE" && input.status === "SUCCESS") {
    nextStatus = "NOT_INSTALLED";
    installedVersionId = null;
    installedVersionCode = null;
    installedVersionName = null;
  } else if ((input.action === "INSTALL" || input.action === "UPDATE") && input.status === "SUCCESS") {
    nextStatus = "INSTALLED";
    installedVersionId = version?.id ?? null;
    installedVersionCode = resolvedVersionCode;
    installedVersionName = resolvedVersionName;
  } else if (input.status === "FAILED") {
    nextStatus = "INSTALL_FAILED";
  } else if (input.action === "OPEN" && input.status === "SUCCESS") {
    lastOpenedAt = new Date();
  }

  const state = await prisma.deviceAppState.upsert({
    where: {
      deviceId_appId: {
        deviceId: input.deviceId,
        appId: input.appId,
      },
    },
    create: {
      deviceId: input.deviceId,
      appId: input.appId,
      installedVersionId,
      installedVersionCode,
      installedVersionName,
      status: nextStatus,
      lastOpenedAt,
      lastReportedAt: new Date(),
      notes: input.notes,
    },
    update: {
      installedVersionId,
      installedVersionCode,
      installedVersionName,
      status: nextStatus,
      lastOpenedAt,
      lastReportedAt: new Date(),
      notes: input.notes,
    },
  });

  await prisma.device.update({
    where: {
      id: input.deviceId,
    },
    data: {
      lastSeenAt: new Date(),
    },
  });

  await prisma.installationLog.create({
    data: {
      appId: input.appId,
      appVersionId: version?.id,
      deviceId: input.deviceId,
      userId: user.userId,
      action: input.action,
      status: input.status,
      requestedVersionCode: version?.versionCode ?? resolvedVersionCode ?? undefined,
      installedVersionCode: resolvedVersionCode ?? undefined,
      details: input.notes,
    },
  });

  return {
    state,
    updateAvailable:
      latestVersionCode !== null && installedVersionCode !== null
        ? installedVersionCode < latestVersionCode
        : false,
  };
}

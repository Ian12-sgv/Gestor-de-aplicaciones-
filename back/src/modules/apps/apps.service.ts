import { Prisma } from "@prisma/client";
import fs from "node:fs";
import path from "node:path";
import { hasPermission, PERMISSIONS } from "../../config/domain";
import { env } from "../../config/env";
import { prisma } from "../../config/prisma";
import { resolveStoredApkPath, storedApkExists } from "../../utils/apk";
import { ApiError } from "../../utils/api-error";
import type { AuthenticatedRequestUser } from "../auth/auth.types";
import {
  imageContentTypeForPath,
  isManagedIconPath,
  resolveStoredMediaPath,
} from "../../utils/media";

function isAdmin(user?: AuthenticatedRequestUser): boolean {
  return user !== undefined && hasPermission(user.roles, PERMISSIONS.APP_CATALOG_BYPASS);
}

function accessibleAppsWhere(user?: AuthenticatedRequestUser): Prisma.AppWhereInput {
  if (!user) {
    return {
      status: "ACTIVE",
      requiresExplicitAccess: false,
    };
  }

  if (isAdmin(user)) {
    return {
      status: "ACTIVE",
    };
  }

  return {
    status: "ACTIVE",
    OR: [
      { requiresExplicitAccess: false },
      {
        userPermissions: {
          some: {
            userId: user.userId,
            canView: true,
          },
        },
      },
      {
        rolePermissions: {
          some: {
            canView: true,
            role: {
              code: {
                in: user.roles,
              },
            },
          },
        },
      },
    ],
  };
}

function installableAppsWhere(user?: AuthenticatedRequestUser): Prisma.AppWhereInput {
  if (!user) {
    return {
      status: "ACTIVE",
      requiresExplicitAccess: false,
    };
  }

  if (isAdmin(user)) {
    return {
      status: "ACTIVE",
    };
  }

  return {
    status: "ACTIVE",
    OR: [
      { requiresExplicitAccess: false },
      {
        userPermissions: {
          some: {
            userId: user.userId,
            canInstall: true,
          },
        },
      },
      {
        rolePermissions: {
          some: {
            canInstall: true,
            role: {
              code: {
                in: user.roles,
              },
            },
          },
        },
      },
    ],
  };
}

const versionsInclude = {
  orderBy: {
    versionCode: "desc" as const,
  },
};

const deviceStatesInclude = {
  include: {
    installedVersion: true,
  },
} satisfies Prisma.DeviceAppStateFindManyArgs;

type AppVersionRecord = Prisma.AppVersionGetPayload<Record<string, never>>;
type AppBaseRecord = Prisma.AppGetPayload<{
  include: {
    versions: typeof versionsInclude;
  };
}>;

type DeviceStateRecord = Prisma.DeviceAppStateGetPayload<{
  include: typeof deviceStatesInclude.include;
}>;

type AppRecord = AppBaseRecord & {
  deviceStates: DeviceStateRecord[];
};

function normalizeAppRecord(app: AppBaseRecord | AppRecord): AppRecord {
  return {
    ...app,
    deviceStates: "deviceStates" in app ? app.deviceStates : [],
  };
}

function mapVersionSummary(version: AppVersionRecord) {
  return {
    id: version.id,
    versionName: version.versionName,
    versionCode: version.versionCode,
    changelog: version.changelog,
    isMandatory: version.isMandatory,
    releasedAt: version.releasedAt,
    minSupportedVersionCode: version.minSupportedVersionCode,
  };
}

async function findAccessibleAppOrThrow(
  appId: string,
  user?: AuthenticatedRequestUser,
  deviceId?: string,
): Promise<AppRecord> {
  const include = deviceId
    ? {
        versions: versionsInclude,
        deviceStates: {
          where: { deviceId },
          take: 1,
          ...deviceStatesInclude,
        },
      }
    : {
        versions: versionsInclude,
      };

  const app = await prisma.app.findFirst({
    where: {
      id: appId,
      ...accessibleAppsWhere(user),
    },
    include,
  });

  if (!app) {
    throw new ApiError(404, "Application not found or inaccessible");
  }

  return normalizeAppRecord(app);
}

async function resolveAvailableVersion(
  versions: AppVersionRecord[],
  availabilityCache: Map<string, boolean>,
): Promise<AppVersionRecord | null> {
  for (const version of versions) {
    if (await hasAvailableStoredApk(version.apkPath, availabilityCache)) {
      return version;
    }
  }

  return null;
}

async function hasAvailableStoredApk(
  apkPath: string,
  availabilityCache: Map<string, boolean>,
): Promise<boolean> {
  const resolvedPath = resolveStoredApkPath(env.APK_STORAGE_DIR, apkPath);

  if (!resolvedPath) {
    return false;
  }

  const cachedValue = availabilityCache.get(resolvedPath.filePath);

  if (cachedValue !== undefined) {
    return cachedValue;
  }

  const exists = await storedApkExists(env.APK_STORAGE_DIR, apkPath);
  availabilityCache.set(resolvedPath.filePath, exists);
  return exists;
}

async function mapAppSummary(
  app: AppRecord,
  availabilityCache: Map<string, boolean>,
): Promise<Record<string, unknown> | null> {
  const latestVersion = await resolveAvailableVersion(app.versions, availabilityCache);

  if (!latestVersion) {
    return null;
  }

  const installedState = app.deviceStates[0] ?? null;
  const installedVersionCode = installedState?.installedVersionCode ?? null;
  const updateAvailable =
    installedVersionCode !== null && installedVersionCode < latestVersion.versionCode;

  return {
    id: app.id,
    packageName: app.packageName,
    slug: app.slug,
    displayName: app.displayName,
    shortDescription: app.shortDescription,
    description: app.description,
    iconPath: app.iconPath,
    iconUrl: isManagedIconPath(app.iconPath)
      ? `${env.API_PREFIX}/apps/${app.id}/icon`
      : null,
    bannerPath: app.bannerPath,
    category: app.category,
    status: app.status,
    requiresExplicitAccess: app.requiresExplicitAccess,
    latestVersion: mapVersionSummary(latestVersion),
    installedState: installedState
      ? {
          id: installedState.id,
          status: installedState.status,
          installedVersionId: installedState.installedVersionId,
          installedVersionName: installedState.installedVersionName,
          installedVersionCode,
          lastReportedAt: installedState.lastReportedAt,
          lastOpenedAt: installedState.lastOpenedAt,
        }
      : null,
    updateAvailable,
  };
}

export async function listApps(user?: AuthenticatedRequestUser, deviceId?: string) {
  const include = deviceId
    ? {
        versions: versionsInclude,
        deviceStates: {
          where: { deviceId },
          take: 1,
          ...deviceStatesInclude,
        },
      }
    : {
        versions: versionsInclude,
      };

  const apps = await prisma.app.findMany({
    where: accessibleAppsWhere(user),
    include,
    orderBy: {
      displayName: "asc",
    },
  });

  const availabilityCache = new Map<string, boolean>();
  const summaries = await Promise.all(
    apps.map((app) => mapAppSummary(normalizeAppRecord(app), availabilityCache)),
  );

  return summaries.filter((summary): summary is Record<string, unknown> => summary !== null);
}

export async function getAppById(appId: string, user?: AuthenticatedRequestUser, deviceId?: string) {
  const app = await findAccessibleAppOrThrow(appId, user, deviceId);
  const summary = await mapAppSummary(app, new Map<string, boolean>());

  if (!summary) {
    throw new ApiError(404, "Application has no published APK available.");
  }

  return summary;
}

export async function getLatestVersion(
  appId: string,
  user?: AuthenticatedRequestUser,
  deviceId?: string,
) {
  const app = await findAccessibleAppOrThrow(appId, user, deviceId);
  const latestVersion = await resolveAvailableVersion(app.versions, new Map<string, boolean>());

  if (!latestVersion) {
    throw new ApiError(404, "No released versions with an available APK were found.");
  }

  return {
    appId: app.id,
    latestVersion: mapVersionSummary(latestVersion),
  };
}

export async function getChangelog(appId: string, user?: AuthenticatedRequestUser) {
  const app = await prisma.app.findFirst({
    where: {
      id: appId,
      ...accessibleAppsWhere(user),
    },
    select: {
      id: true,
      displayName: true,
      packageName: true,
      versions: {
        orderBy: {
          versionCode: "desc",
        },
        select: {
          id: true,
          versionName: true,
          versionCode: true,
          changelog: true,
          isMandatory: true,
          releasedAt: true,
          minSupportedVersionCode: true,
          apkPath: true,
        },
      },
    },
  });

  if (!app) {
    throw new ApiError(404, "Application not found or inaccessible");
  }

  const availabilityCache = new Map<string, boolean>();
  const availableVersions = (
    await Promise.all(
      app.versions.map(async (version) =>
        (await hasAvailableStoredApk(version.apkPath, availabilityCache))
          ? {
              id: version.id,
              versionName: version.versionName,
              versionCode: version.versionCode,
              changelog: version.changelog,
              isMandatory: version.isMandatory,
              releasedAt: version.releasedAt,
              minSupportedVersionCode: version.minSupportedVersionCode,
            }
          : null,
      ),
    )
  ).filter((version): version is Exclude<typeof version, null> => version !== null);

  if (availableVersions.length === 0) {
    throw new ApiError(404, "No released versions with an available APK were found.");
  }

  return {
    id: app.id,
    displayName: app.displayName,
    packageName: app.packageName,
    versions: availableVersions,
  };
}

export async function getAppIcon(appId: string, user?: AuthenticatedRequestUser) {
  const app = await prisma.app.findFirst({
    where: {
      id: appId,
      ...accessibleAppsWhere(user),
    },
    select: {
      iconPath: true,
    },
  });

  if (!app || !isManagedIconPath(app.iconPath)) {
    throw new ApiError(404, "Application icon not found or inaccessible");
  }

  const resolvedPath = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, app.iconPath);
  const contentType = imageContentTypeForPath(app.iconPath);

  if (!resolvedPath || !contentType || !fs.existsSync(resolvedPath.filePath)) {
    throw new ApiError(404, "Application icon not found or inaccessible");
  }

  return {
    filePath: resolvedPath.filePath,
    contentType,
  };
}

export async function prepareDownload(
  appId: string,
  user: AuthenticatedRequestUser | undefined,
  options: {
    deviceId?: string;
    versionCode?: number;
  },
) {
  const app = await prisma.app.findFirst({
    where: {
      id: appId,
      ...installableAppsWhere(user),
    },
    include: {
      versions: {
        where: options.versionCode
          ? {
              versionCode: options.versionCode,
            }
          : undefined,
        orderBy: {
          versionCode: "desc",
        },
      },
    },
  });

  if (!app) {
    throw new ApiError(404, "Application not found or inaccessible");
  }

  const version = options.versionCode
    ? app.versions[0] ?? null
    : await resolveAvailableVersion(app.versions, new Map<string, boolean>());

  if (!version) {
    throw new ApiError(404, "Requested version not found");
  }

  const resolvedPath = resolveStoredApkPath(env.APK_STORAGE_DIR, version.apkPath);

  if (!resolvedPath) {
    throw new ApiError(500, "Invalid APK path configuration");
  }

  const apkExists = await storedApkExists(env.APK_STORAGE_DIR, version.apkPath);

  if (!apkExists) {
    throw new ApiError(404, "APK file not found in storage");
  }

  await prisma.installationLog.create({
    data: {
      appId: app.id,
      appVersionId: version.id,
      deviceId: options.deviceId,
      userId: user?.userId,
      action: "DOWNLOAD",
      status: "SUCCESS",
      requestedVersionCode: version.versionCode,
      details: user ? "APK download served by authenticated endpoint" : "APK download served by public catalog endpoint",
    },
  });

  return {
    filePath: resolvedPath.filePath,
    fileName: `${app.slug}-v${version.versionCode}${path.extname(resolvedPath.filePath) || ".apk"}`,
    version: {
      id: version.id,
      versionName: version.versionName,
      versionCode: version.versionCode,
      isMandatory: version.isMandatory,
    },
  };
}
export async function preparePdbStoreDownload() {
  const app = await prisma.app.findFirst({
    where: {
      packageName: "com.company.corporateappstore.corporate_app_store",
      status: "ACTIVE",
      requiresExplicitAccess: false,
    },
    select: {
      id: true,
    },
  });

  if (!app) {
    throw new ApiError(404, "PDBStore is not available for public download");
  }

  return prepareDownload(app.id, undefined, {});
}


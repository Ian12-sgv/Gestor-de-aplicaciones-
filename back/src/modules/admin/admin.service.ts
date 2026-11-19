import path from "node:path";
import fs from "node:fs";
import { Prisma } from "@prisma/client";
import { env } from "../../config/env";
import { prisma } from "../../config/prisma";
import {
  inspectApkFile,
  normalizeRelativeStoragePath,
  resolveStoredApkPath,
} from "../../utils/apk";
import { ApiError } from "../../utils/api-error";
import { readApkManifestMetadata, type ApkManifestMetadata } from "../../utils/apk-manifest";
import {
  ensureDirectory,
  moveFileToDirectory,
  removeDirectoryIfExists,
  removeFileIfExists,
} from "../../utils/fs";
import {
  createIconRelativePath,
  imageContentTypeForPath,
  inspectUploadedImage,
  isManagedIconPath,
  resolveStoredMediaPath,
} from "../../utils/media";
import { hashPassword } from "../../utils/password";
import { slugify } from "../../utils/strings";
import { revokeAllSessionsForUser } from "../auth/auth.service";
import type { AuthenticatedRequestUser } from "../auth/auth.types";
import type {
  CreateAppFromApkInput,
  CreateAppInput,
  CreateAppVersionInput,
  CreateUserInput,
  ListInstallationLogsQuery,
  RevokeUserAccessInput,
  UpdateAppInput,
  UpdateAppStatusInput,
  UpdateUserStatusInput,
  UpdateVersionMandatoryInput,
  UpsertAppUserAccessInput,
} from "./admin.schemas";

export async function createApp(input: CreateAppInput, user: AuthenticatedRequestUser) {
  const existing = await prisma.app.findFirst({
    where: {
      OR: [{ packageName: input.packageName }, { slug: input.slug ?? slugify(input.displayName) }],
    },
    select: { packageName: true },
  });

  if (existing) {
    throw new ApiError(
      409,
      existing.packageName === input.packageName
        ? `An application with package ${input.packageName} already exists.`
        : "An application with the same slug already exists.",
    );
  }

  const app = await prisma.app.create({
    data: {
      packageName: input.packageName,
      slug: input.slug ?? slugify(input.displayName),
      displayName: input.displayName,
      shortDescription: input.shortDescription,
      description: input.description,
      iconPath: input.iconPath,
      bannerPath: input.bannerPath,
      category: input.category,
      requiresExplicitAccess: input.requiresExplicitAccess ?? false,
      status: input.status ?? "DRAFT",
      createdById: user.userId,
    },
  });

  return app;
}

export async function listAdminApps() {
  return prisma.app.findMany({
    orderBy: { updatedAt: "desc" },
    select: {
      id: true,
      packageName: true,
      slug: true,
      displayName: true,
      shortDescription: true,
      description: true,
      iconPath: true,
      category: true,
      status: true,
      requiresExplicitAccess: true,
      createdAt: true,
      updatedAt: true,
      versions: {
        orderBy: { versionCode: "desc" },
        select: {
          id: true,
          versionName: true,
          versionCode: true,
          isMandatory: true,
          releasedAt: true,
          changelog: true,
          fileSizeBytes: true,
          originalFileName: true,
          createdBy: {
            select: {
              username: true,
            },
          },
        },
      },
    },
  });
}

export async function updateApp(appId: string, input: UpdateAppInput) {
  try {
    return await prisma.app.update({
      where: { id: appId },
      data: {
        slug: input.slug,
        displayName: input.displayName,
        shortDescription: input.shortDescription,
        description: input.description,
        category: input.category,
        requiresExplicitAccess: input.requiresExplicitAccess,
      },
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2025") {
      throw new ApiError(404, "Application not found");
    }

    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      throw new ApiError(409, "An application with the same slug already exists.");
    }

    throw error;
  }
}

export async function getAdminAppIcon(appId: string) {
  const app = await prisma.app.findUnique({
    where: { id: appId },
    select: { iconPath: true },
  });

  if (!app || !isManagedIconPath(app.iconPath)) {
    throw new ApiError(404, "Application icon not found");
  }

  const resolvedPath = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, app.iconPath);
  const contentType = imageContentTypeForPath(app.iconPath);

  if (!resolvedPath || !contentType || !fs.existsSync(resolvedPath.filePath)) {
    throw new ApiError(404, "Application icon not found");
  }

  return {
    filePath: resolvedPath.filePath,
    contentType,
  };
}

export async function createAppVersion(
  appId: string,
  input: CreateAppVersionInput,
  uploadedFile: Express.Multer.File | undefined,
  user: AuthenticatedRequestUser,
  options?: {
    cleanupSourceFileOnError?: boolean;
  },
) {
  const cleanupSourceFileOnError = options?.cleanupSourceFileOnError ?? true;
  const app = await prisma.app.findUnique({
    where: {
      id: appId,
    },
  });

  if (!app) {
    if (cleanupSourceFileOnError) {
      await removeFileIfExists(uploadedFile?.path);
    }

    throw new ApiError(404, "Application not found");
  }

  if (!uploadedFile && !input.apkRelativePath) {
    throw new ApiError(400, "An uploaded APK or apkRelativePath is required");
  }

  let versionInfo: { versionCode: number; versionName: string };

  try {
    versionInfo = await resolveVersionInfo(app.packageName, input, uploadedFile?.path ?? null);
  } catch (error) {
    if (cleanupSourceFileOnError) {
      await removeFileIfExists(uploadedFile?.path);
    }

    throw error;
  }

  const duplicateVersion = await prisma.appVersion.findUnique({
    where: {
      appId_versionCode: {
        appId,
        versionCode: versionInfo.versionCode,
      },
    },
    select: {
      id: true,
    },
  });

  if (duplicateVersion) {
    if (cleanupSourceFileOnError) {
      await removeFileIfExists(uploadedFile?.path);
    }

    throw new ApiError(
      409,
      `Version code ${versionInfo.versionCode} already exists for ${app.displayName}.`,
    );
  }

  let uploadedSourcePath: string | null = uploadedFile?.path ?? null;
  let persistedFilePath: string | null = null;

  try {
    const resolvedApk = uploadedFile
      ? await prepareUploadedApk(app, input, uploadedFile, versionInfo.versionCode)
      : await prepareReferencedApk(input);

    if (uploadedFile) {
      uploadedSourcePath = null;
      persistedFilePath = resolvedApk.filePath;
    }

    const version = await prisma.appVersion.create({
      data: {
        appId,
        versionName: versionInfo.versionName,
        versionCode: versionInfo.versionCode,
        changelog: input.changelog,
        sha256: resolvedApk.metadata.sha256,
        minSupportedVersionCode: input.minSupportedVersionCode,
        isMandatory: input.isMandatory ?? false,
        apkPath: resolvedApk.relativePath,
        originalFileName: resolvedApk.metadata.originalFileName,
        contentType: resolvedApk.metadata.contentType,
        fileExtension: resolvedApk.metadata.fileExtension,
        archiveEntryCount: resolvedApk.metadata.archiveEntryCount,
        fileSizeBytes: resolvedApk.metadata.fileSizeBytes,
        createdById: user.userId,
      },
    });

    return version;
  } catch (error) {
    if (cleanupSourceFileOnError) {
      await removeFileIfExists(uploadedSourcePath);
    }

    await removeFileIfExists(persistedFilePath);

    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2002"
    ) {
      throw new ApiError(
        409,
        `Version code ${versionInfo.versionCode} already exists for ${app.displayName}.`,
      );
    }

    throw error;
  }
}

export async function uploadAppIcon(
  appId: string,
  uploadedFile: Express.Multer.File | undefined,
) {
  if (!uploadedFile) {
    throw new ApiError(400, "An icon image is required.");
  }

  let persistedFilePath: string | null = null;

  try {
    const app = await prisma.app.findUnique({
      where: { id: appId },
      select: { id: true, iconPath: true },
    });

    if (!app) {
      throw new ApiError(404, "Application not found");
    }

    const image = await inspectUploadedImage(uploadedFile);
    const relativePath = createIconRelativePath(image.contentType);
    const resolvedPath = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, relativePath);

    if (!resolvedPath) {
      throw new ApiError(500, "Invalid media path configuration");
    }

    persistedFilePath = await moveFileToDirectory(
      uploadedFile.path,
      path.dirname(resolvedPath.filePath),
      path.basename(resolvedPath.filePath),
    );

    const updatedApp = await prisma.app.update({
      where: { id: appId },
      data: { iconPath: relativePath },
    });
    persistedFilePath = null;

    if (isManagedIconPath(app.iconPath)) {
      const previousPath = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, app.iconPath);
      await removeFileIfExists(previousPath?.filePath);
    }

    return updatedApp;
  } catch (error) {
    await removeFileIfExists(uploadedFile.path);
    await removeFileIfExists(persistedFilePath);
    throw error;
  }
}

export async function deleteAppIcon(appId: string) {
  const app = await prisma.app.findUnique({
    where: { id: appId },
    select: { id: true, iconPath: true },
  });

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  const updatedApp = await prisma.app.update({
    where: { id: appId },
    data: { iconPath: null },
  });

  if (isManagedIconPath(app.iconPath)) {
    const previousPath = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, app.iconPath);
    await removeFileIfExists(previousPath?.filePath);
  }

  return updatedApp;
}

export async function updateAppStatus(appId: string, input: UpdateAppStatusInput) {
  try {
    return await prisma.app.update({
      where: {
        id: appId,
      },
      data: {
        status: input.status,
      },
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2025") {
      throw new ApiError(404, "Application not found");
    }

    throw error;
  }
}

export async function deleteAppFromStore(appId: string, actor: AuthenticatedRequestUser) {
  const app = await prisma.app.findUnique({
    where: {
      id: appId,
    },
    select: {
      id: true,
      displayName: true,
      packageName: true,
      iconPath: true,
      versions: {
        select: {
          apkPath: true,
        },
      },
    },
  });

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  const result = await prisma.$transaction(async (tx) => {
    const installationLogs = await tx.installationLog.deleteMany({
      where: {
        appId,
      },
    });
    const deviceStates = await tx.deviceAppState.deleteMany({
      where: {
        appId,
      },
    });
    const userPermissions = await tx.appUserPermission.deleteMany({
      where: {
        appId,
      },
    });
    const rolePermissions = await tx.appRolePermission.deleteMany({
      where: {
        appId,
      },
    });
    const versions = await tx.appVersion.deleteMany({
      where: {
        appId,
      },
    });
    const deletedApp = await tx.app.delete({
      where: {
        id: appId,
      },
      select: {
        id: true,
        displayName: true,
        packageName: true,
      },
    });

    return {
      app: deletedApp,
      deletedCounts: {
        installationLogs: installationLogs.count,
        deviceStates: deviceStates.count,
        userPermissions: userPermissions.count,
        rolePermissions: rolePermissions.count,
        versions: versions.count,
      },
    };
  });

  await removeDirectoryIfExists(path.join(env.APK_STORAGE_DIR, app.packageName));
  if (isManagedIconPath(app.iconPath)) {
    const iconFile = resolveStoredMediaPath(env.MEDIA_STORAGE_DIR, app.iconPath);
    await removeFileIfExists(iconFile?.filePath);
  }


  return {
    ...result,
    deletedByUserId: actor.userId,
  };
}

export async function updateVersionMandatory(
  versionId: string,
  input: UpdateVersionMandatoryInput,
) {
  const version = await prisma.appVersion.update({
    where: {
      id: versionId,
    },
    data: {
      isMandatory: input.isMandatory,
    },
  });

  return version;
}

export async function createUser(input: CreateUserInput) {
  const existingUser = await prisma.user.findFirst({
    where: {
      OR: [{ email: input.email }, { username: input.username }],
    },
    select: {
      id: true,
      email: true,
      username: true,
    },
  });

  if (existingUser) {
    throw new ApiError(
      409,
      "A user with the same email or username already exists.",
      existingUser,
    );
  }

  const roles = await prisma.role.findMany({
    where: {
      code: {
        in: input.roleCodes,
      },
    },
  });

  if (roles.length !== input.roleCodes.length) {
    throw new ApiError(400, "One or more roleCodes do not exist.");
  }

  const passwordHash = await hashPassword(input.password);

  const user = await prisma.user.create({
    data: {
      email: input.email,
      username: input.username,
      passwordHash,
      firstName: input.firstName,
      lastName: input.lastName,
      status: input.status,
      passwordMustChange: true,
      roles: {
        create: roles.map((role) => ({
          roleId: role.id,
        })),
      },
    },
    include: {
      roles: {
        include: {
          role: true,
        },
      },
    },
  });

  return {
    id: user.id,
    email: user.email,
    username: user.username,
    firstName: user.firstName,
    lastName: user.lastName,
    status: user.status,
    passwordMustChange: user.passwordMustChange,
    roles: user.roles.map((entry) => entry.role.code),
  };
}

export async function upsertAppUserAccess(
  appId: string,
  userId: string,
  input: UpsertAppUserAccessInput,
) {
  const [app, user] = await Promise.all([
    prisma.app.findUnique({
      where: { id: appId },
      select: {
        id: true,
        displayName: true,
      },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        username: true,
      },
    }),
  ]);

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  if (!input.canView && !input.canInstall) {
    await prisma.appUserPermission.deleteMany({
      where: {
        appId,
        userId,
      },
    });

    return {
      appId,
      userId,
      canView: false,
      canInstall: false,
      removed: true,
    };
  }

  const permission = await prisma.appUserPermission.upsert({
    where: {
      appId_userId: {
        appId,
        userId,
      },
    },
    create: {
      appId,
      userId,
      canView: input.canView,
      canInstall: input.canInstall,
    },
    update: {
      canView: input.canView,
      canInstall: input.canInstall,
    },
  });

  return {
    id: permission.id,
    appId,
    userId,
    canView: permission.canView,
    canInstall: permission.canInstall,
    removed: false,
  };
}

export async function upsertAppRoleAccess(
  appId: string,
  roleCode: string,
  input: UpsertAppUserAccessInput,
) {
  const [app, role] = await Promise.all([
    prisma.app.findUnique({
      where: { id: appId },
      select: {
        id: true,
        displayName: true,
      },
    }),
    prisma.role.findUnique({
      where: { code: roleCode },
      select: {
        id: true,
        code: true,
        name: true,
      },
    }),
  ]);

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  if (!role) {
    throw new ApiError(404, "Role not found");
  }

  if (!input.canView && !input.canInstall) {
    await prisma.appRolePermission.deleteMany({
      where: {
        appId,
        roleId: role.id,
      },
    });

    return {
      appId,
      roleCode,
      canView: false,
      canInstall: false,
      removed: true,
    };
  }

  const permission = await prisma.appRolePermission.upsert({
    where: {
      appId_roleId: {
        appId,
        roleId: role.id,
      },
    },
    create: {
      appId,
      roleId: role.id,
      canView: input.canView,
      canInstall: input.canInstall,
    },
    update: {
      canView: input.canView,
      canInstall: input.canInstall,
    },
  });

  return {
    id: permission.id,
    appId,
    roleCode,
    canView: permission.canView,
    canInstall: permission.canInstall,
    removed: false,
  };
}

export async function listInstallationLogs(query: ListInstallationLogsQuery) {
  const logs = await prisma.installationLog.findMany({
    where: {
      appId: query.appId,
      userId: query.userId,
      deviceId: query.deviceId,
      action: query.action,
    },
    take: query.limit,
    orderBy: {
      createdAt: "desc",
    },
    include: {
      app: {
        select: {
          id: true,
          displayName: true,
          packageName: true,
        },
      },
      appVersion: {
        select: {
          id: true,
          versionName: true,
          versionCode: true,
        },
      },
      user: {
        select: {
          id: true,
          email: true,
          username: true,
        },
      },
      device: {
        select: {
          id: true,
          deviceIdentifier: true,
          name: true,
        },
      },
    },
  });

  return logs;
}

export async function revokeUserAccess(
  userId: string,
  input: RevokeUserAccessInput,
  actor: AuthenticatedRequestUser,
) {
  if (userId === actor.userId) {
    throw new ApiError(400, "You cannot revoke your own access.");
  }

  const targetUser = await prisma.user.findUnique({
    where: { id: userId },
    select: {
      id: true,
    },
  });

  if (!targetUser) {
    throw new ApiError(404, "User not found");
  }

  const updatedUser = await prisma.user.update({
    where: { id: userId },
    data: {
      status: input.status,
    },
    include: {
      roles: {
        include: {
          role: true,
        },
      },
    },
  });

  await revokeAllSessionsForUser(userId);

  const revokedUser = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      roles: {
        include: {
          role: true,
        },
      },
    },
  });

  if (!revokedUser) {
    throw new ApiError(404, "User not found");
  }

  return {
    userId: revokedUser.id,
    status: revokedUser.status,
    sessionVersion: revokedUser.sessionVersion,
    revokedByUserId: actor.userId,
    roles: revokedUser.roles.map((entry) => entry.role.code),
    revokedAt: new Date().toISOString(),
  };
}

export async function createAppFromApk(
  input: CreateAppFromApkInput,
  uploadedFile: Express.Multer.File | undefined,
  user: AuthenticatedRequestUser,
) {
  if (!uploadedFile) {
    throw new ApiError(400, "An uploaded APK is required");
  }

  let manifest: ApkManifestMetadata;

  try {
    manifest = await readApkManifestMetadata(uploadedFile.path);
  } catch (error) {
    await removeFileIfExists(uploadedFile.path);
    throw error;
  }

  const displayName = input.displayName ?? manifest.displayName ?? manifest.packageName;

  let app: Awaited<ReturnType<typeof createApp>>;

  try {
    app = await createApp(
      {
        packageName: manifest.packageName,
        displayName: displayName.slice(0, 150),
        slug: input.slug,
        shortDescription: input.shortDescription,
        category: input.category,
        requiresExplicitAccess: input.requiresExplicitAccess,
        status: "DRAFT",
      },
      user,
    );
  } catch (error) {
    await removeFileIfExists(uploadedFile.path);
    throw error;
  }

  try {
    const version = await createAppVersion(
      app.id,
      { changelog: input.changelog, isMandatory: input.isMandatory },
      uploadedFile,
      user,
    );

    return { app, version };
  } catch (error) {
    // The version is what makes the entry useful: roll back the empty app on failure.
    await prisma.app.delete({ where: { id: app.id } }).catch(() => undefined);
    throw error;
  }
}

export async function listUsers() {
  const users = await prisma.user.findMany({
    orderBy: [{ status: "asc" }, { username: "asc" }],
    select: {
      id: true,
      email: true,
      username: true,
      firstName: true,
      lastName: true,
      status: true,
      passwordMustChange: true,
      lastLoginAt: true,
      createdAt: true,
      roles: {
        select: {
          role: {
            select: {
              code: true,
            },
          },
        },
      },
      _count: {
        select: {
          devices: true,
        },
      },
    },
  });

  return users.map(({ roles, _count, ...user }) => ({
    ...user,
    roles: roles.map((entry) => entry.role.code),
    deviceCount: _count.devices,
  }));
}

export async function updateUserStatus(
  userId: string,
  input: UpdateUserStatusInput,
  actor: AuthenticatedRequestUser,
) {
  if (userId === actor.userId) {
    throw new ApiError(400, "You cannot change your own status.");
  }

  const targetUser = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true },
  });

  if (!targetUser) {
    throw new ApiError(404, "User not found");
  }

  const user = await prisma.user.update({
    where: { id: userId },
    data: { status: input.status },
    select: { id: true, status: true },
  });

  if (input.status !== "ACTIVE") {
    await revokeAllSessionsForUser(userId);
  }

  return user;
}

export async function listAppAccess(appId: string) {
  const app = await prisma.app.findUnique({
    where: { id: appId },
    select: {
      id: true,
      requiresExplicitAccess: true,
      userPermissions: {
        orderBy: { createdAt: "asc" },
        select: {
          canView: true,
          canInstall: true,
          user: {
            select: {
              id: true,
              username: true,
              email: true,
              status: true,
            },
          },
        },
      },
      rolePermissions: {
        orderBy: { createdAt: "asc" },
        select: {
          canView: true,
          canInstall: true,
          role: {
            select: {
              code: true,
              name: true,
            },
          },
        },
      },
    },
  });

  if (!app) {
    throw new ApiError(404, "Application not found");
  }

  return {
    appId: app.id,
    requiresExplicitAccess: app.requiresExplicitAccess,
    users: app.userPermissions.map(({ user, ...permission }) => ({ ...permission, user })),
    roles: app.rolePermissions.map(({ role, ...permission }) => ({
      ...permission,
      roleCode: role.code,
      roleName: role.name,
    })),
  };
}

async function prepareUploadedApk(
  app: {
    packageName: string;
    slug: string;
  },
  input: CreateAppVersionInput,
  uploadedFile: Express.Multer.File,
  versionCode: number,
) {
  const inspection = await inspectApkFile(uploadedFile.path, {
    declaredFileName: uploadedFile.originalname,
    contentType: uploadedFile.mimetype,
    expectedSha256: input.sha256,
  });

  const storageRoot = env.APK_STORAGE_DIR;
  const versionDirectory = path.join(storageRoot, app.packageName, String(versionCode));
  const fileName = `${app.slug}-v${versionCode}.apk`;

  await ensureDirectory(versionDirectory);
  const finalPath = await moveFileToDirectory(uploadedFile.path, versionDirectory, fileName);
  const resolvedPath = resolveStoredApkPath(storageRoot, path.relative(storageRoot, finalPath));

  if (!resolvedPath) {
    throw new ApiError(500, "Invalid APK path configuration");
  }

  return {
    filePath: resolvedPath.filePath,
    relativePath: resolvedPath.relativePath,
    metadata: inspection,
  };
}

// Reads the version from the APK itself so devices compare against the real versionCode, and
// guards against uploading an APK into the wrong catalog entry (e.g. the store APK as a version
// of another app), which devices would download but never be able to install.
async function resolveVersionInfo(
  expectedPackageName: string,
  input: CreateAppVersionInput,
  apkFilePath: string | null,
): Promise<{ versionCode: number; versionName: string }> {
  if (!apkFilePath) {
    if (!input.versionCode || !input.versionName) {
      throw new ApiError(400, "versionName and versionCode are required when using apkRelativePath.");
    }

    return { versionCode: input.versionCode, versionName: input.versionName };
  }

  const manifest: ApkManifestMetadata = await readApkManifestMetadata(apkFilePath);

  if (manifest.packageName !== expectedPackageName) {
    throw new ApiError(
      400,
      `The APK belongs to package ${manifest.packageName}, but this app is ${expectedPackageName}. Upload it to the matching app.`,
      { apkPackageName: manifest.packageName, expectedPackageName },
    );
  }

  if (input.versionCode !== undefined && manifest.versionCode !== input.versionCode) {
    throw new ApiError(
      400,
      `The APK has versionCode ${manifest.versionCode} (${manifest.versionName}), but ${input.versionCode} was entered.`,
      {
        apkVersionCode: manifest.versionCode,
        apkVersionName: manifest.versionName,
        expectedVersionCode: input.versionCode,
      },
    );
  }

  return {
    versionCode: manifest.versionCode,
    versionName: input.versionName ?? manifest.versionName,
  };
}

async function prepareReferencedApk(input: CreateAppVersionInput) {
  const storageRoot = env.APK_STORAGE_DIR;
  const normalizedRelativePath = normalizeRelativeStoragePath(input.apkRelativePath ?? "");
  const resolvedPath = resolveStoredApkPath(storageRoot, normalizedRelativePath);

  if (!resolvedPath) {
    throw new ApiError(400, "apkRelativePath must stay inside APK_STORAGE_DIR.");
  }

  const inspection = await inspectApkFile(resolvedPath.filePath, {
    declaredFileName: path.basename(normalizedRelativePath),
    expectedSha256: input.sha256,
  });

  return {
    filePath: resolvedPath.filePath,
    relativePath: resolvedPath.relativePath,
    metadata: inspection,
  };
}

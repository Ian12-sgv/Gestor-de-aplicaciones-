import { readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { env } from "../../config/env";
import { prisma } from "../../config/prisma";
import { ApiError } from "../../utils/api-error";
import { readApkManifestMetadata } from "../../utils/apk-manifest";
import { ensureDirectory, moveFileToDirectory } from "../../utils/fs";
import { logDebug, logError, logInfo, logWarn } from "../../utils/logger";
import { slugify } from "../../utils/strings";
import type { AuthenticatedRequestUser } from "../auth/auth.types";
import { createApp, createAppVersion, updateAppStatus } from "./admin.service";

const DROP_ZONE_DIRECTORIES = ["", ".incoming"] as const;
const PROCESSING_DIRECTORY_NAME = ".processing";
const FAILED_DIRECTORY_NAME = ".failed";
const DUPLICATE_DIRECTORY_NAME = ".duplicate";

type DropZoneFile = {
  filePath: string;
  directoryLabel: "root" | ".incoming";
  fileName: string;
  size: number;
  mtimeMs: number;
};

type DropZoneObservation = {
  size: number;
  mtimeMs: number;
  stableSinceMs: number;
};

export type AutoImportResult = {
  result: "published" | "duplicate" | "failed";
  sourceFilePath: string;
  packageName?: string;
  versionCode?: number;
  versionName?: string;
  displayName?: string | null;
  appId?: string;
  versionId?: string;
  finalApkPath?: string;
  archivePath?: string;
  reason?: string;
};

export type AutoImportScanSummary = {
  scannedFiles: number;
  pendingFiles: number;
  publishedCount: number;
  duplicateCount: number;
  failedCount: number;
  results: AutoImportResult[];
};

export class ApkAutoImportWorker {
  private readonly observations = new Map<string, DropZoneObservation>();
  private timer: NodeJS.Timeout | null = null;
  private activeScan: Promise<AutoImportScanSummary> | null = null;

  start(): void {
    if (this.timer) {
      return;
    }

    logInfo("apk.auto_import.started", {
      storageRoot: env.APK_STORAGE_DIR,
      pollIntervalMs: env.APK_AUTO_IMPORT_POLL_INTERVAL_MS,
      stableMs: env.APK_AUTO_IMPORT_STABLE_MS,
    });

    void this.scan();
    this.timer = setInterval(() => {
      void this.scan();
    }, env.APK_AUTO_IMPORT_POLL_INTERVAL_MS);
  }

  async stop(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }

    if (this.activeScan) {
      await this.activeScan;
    }

    logInfo("apk.auto_import.stopped");
  }

  async scan(): Promise<AutoImportScanSummary> {
    if (this.activeScan) {
      return this.activeScan;
    }

    this.activeScan = scanDroppedApks({
      observations: this.observations,
      ignoreStability: false,
    })
      .catch((error) => {
        logError("apk.auto_import.scan_failed", {
          error: error instanceof Error ? error.message : String(error),
        });

        return {
          scannedFiles: 0,
          pendingFiles: 0,
          publishedCount: 0,
          duplicateCount: 0,
          failedCount: 0,
          results: [],
        };
      })
      .finally(() => {
        this.activeScan = null;
      });

    return this.activeScan;
  }
}

export async function runApkAutoImportOnce(): Promise<AutoImportScanSummary> {
  return scanDroppedApks({
    observations: new Map<string, DropZoneObservation>(),
    ignoreStability: true,
  });
}

async function scanDroppedApks(options: {
  observations: Map<string, DropZoneObservation>;
  ignoreStability: boolean;
}): Promise<AutoImportScanSummary> {
  const now = Date.now();
  const files = await listDropZoneFiles();
  const eligibleFiles: DropZoneFile[] = [];
  let pendingFiles = 0;

  synchronizeObservations(options.observations, files, now);

  for (const file of files) {
    const observation = options.observations.get(file.filePath);

    if (!observation) {
      continue;
    }

    const isStable =
      options.ignoreStability || now - observation.stableSinceMs >= env.APK_AUTO_IMPORT_STABLE_MS;

    if (isStable) {
      eligibleFiles.push(file);
      continue;
    }

    pendingFiles += 1;
  }

  const results: AutoImportResult[] = [];

  for (const file of eligibleFiles) {
    options.observations.delete(file.filePath);
    results.push(await importDropZoneFile(file));
  }

  const summary = {
    scannedFiles: files.length,
    pendingFiles,
    publishedCount: results.filter((result) => result.result === "published").length,
    duplicateCount: results.filter((result) => result.result === "duplicate").length,
    failedCount: results.filter((result) => result.result === "failed").length,
    results,
  };

  if (results.length > 0 || pendingFiles > 0) {
    logDebug("apk.auto_import.scan_summary", summary);
  }

  return summary;
}

function synchronizeObservations(
  observations: Map<string, DropZoneObservation>,
  files: DropZoneFile[],
  now: number,
): void {
  const currentPaths = new Set(files.map((file) => file.filePath));

  for (const file of files) {
    const existing = observations.get(file.filePath);

    if (!existing) {
      observations.set(file.filePath, {
        size: file.size,
        mtimeMs: file.mtimeMs,
        stableSinceMs: now,
      });
      continue;
    }

    if (existing.size !== file.size || existing.mtimeMs !== file.mtimeMs) {
      observations.set(file.filePath, {
        size: file.size,
        mtimeMs: file.mtimeMs,
        stableSinceMs: now,
      });
    }
  }

  for (const observedPath of observations.keys()) {
    if (!currentPaths.has(observedPath)) {
      observations.delete(observedPath);
    }
  }
}

async function listDropZoneFiles(): Promise<DropZoneFile[]> {
  const files: DropZoneFile[] = [];

  for (const directoryName of DROP_ZONE_DIRECTORIES) {
    const directoryPath = directoryName
      ? path.join(env.APK_STORAGE_DIR, directoryName)
      : env.APK_STORAGE_DIR;
    let entries;

    try {
      entries = await readdir(directoryPath, { withFileTypes: true });
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        continue;
      }

      throw error;
    }

    for (const entry of entries) {
      if (!entry.isFile() || path.extname(entry.name).toLowerCase() !== ".apk") {
        continue;
      }

      const filePath = path.join(directoryPath, entry.name);
      const fileStats = await stat(filePath);

      files.push({
        filePath,
        directoryLabel: directoryName === ".incoming" ? ".incoming" : "root",
        fileName: entry.name,
        size: fileStats.size,
        mtimeMs: fileStats.mtimeMs,
      });
    }
  }

  return files.sort((left, right) => left.mtimeMs - right.mtimeMs);
}

async function importDropZoneFile(file: DropZoneFile): Promise<AutoImportResult> {
  const stagedFileName = buildArchivedFileName(file.fileName);
  const stagedFilePath = await moveFileToDirectory(
    file.filePath,
    path.join(env.APK_STORAGE_DIR, PROCESSING_DIRECTORY_NAME),
    stagedFileName,
  );

  let createdAppId: string | null = null;
  let metadata: Awaited<ReturnType<typeof readApkManifestMetadata>> | null = null;

  try {
    metadata = await readApkManifestMetadata(stagedFilePath);
    const actor = await resolveAutomationActor();
    const ensuredApp = await ensureTargetApp(metadata, actor);
    createdAppId = ensuredApp.created ? ensuredApp.app.id : null;

    const version = await createAppVersion(
      ensuredApp.app.id,
      {
        versionName: metadata.versionName,
        versionCode: metadata.versionCode,
        changelog: buildImportedChangelog(),
        isMandatory: false,
      },
      {
        path: stagedFilePath,
        originalname: file.fileName,
        mimetype: "application/vnd.android.package-archive",
      } as Express.Multer.File,
      actor,
      {
        cleanupSourceFileOnError: false,
      },
    );

    if (ensuredApp.app.status !== "ACTIVE") {
      await updateAppStatus(ensuredApp.app.id, { status: "ACTIVE" });
    }

    logInfo("apk.auto_import.published", {
      sourceFilePath: file.filePath,
      sourceDirectory: file.directoryLabel,
      packageName: metadata.packageName,
      versionCode: metadata.versionCode,
      versionName: metadata.versionName,
      appId: ensuredApp.app.id,
      versionId: version.id,
      publishedApkPath: version.apkPath,
    });

    return {
      result: "published",
      sourceFilePath: file.filePath,
      packageName: metadata.packageName,
      versionCode: metadata.versionCode,
      versionName: metadata.versionName,
      displayName: metadata.displayName,
      appId: ensuredApp.app.id,
      versionId: version.id,
      finalApkPath: version.apkPath,
    };
  } catch (error) {
    if (createdAppId) {
      try {
        await rollbackAutoCreatedApp(createdAppId);
      } catch (rollbackError) {
        logWarn("apk.auto_import.rollback_failed", {
          appId: createdAppId,
          error: rollbackError instanceof Error ? rollbackError.message : String(rollbackError),
        });
      }
    }

    const duplicate = error instanceof ApiError && error.statusCode === 409;
    const archiveDirectory = path.join(
      env.APK_STORAGE_DIR,
      duplicate ? DUPLICATE_DIRECTORY_NAME : FAILED_DIRECTORY_NAME,
    );
    const archivePath = await archiveUnprocessedFile(stagedFilePath, archiveDirectory);

    await writeImportFailureReport(archivePath, {
      archivedAt: new Date().toISOString(),
      sourceFilePath: file.filePath,
      sourceDirectory: file.directoryLabel,
      packageName: metadata?.packageName ?? null,
      versionCode: metadata?.versionCode ?? null,
      versionName: metadata?.versionName ?? null,
      displayName: metadata?.displayName ?? null,
      reason: error instanceof Error ? error.message : String(error),
      statusCode: error instanceof ApiError ? error.statusCode : null,
      details: error instanceof ApiError ? error.details : undefined,
    });

    const logEvent = duplicate ? "apk.auto_import.duplicate" : "apk.auto_import.failed";
    const logFn = duplicate ? logWarn : logError;
    logFn(logEvent, {
      sourceFilePath: file.filePath,
      sourceDirectory: file.directoryLabel,
      archivedPath: archivePath,
      packageName: metadata?.packageName,
      versionCode: metadata?.versionCode,
      reason: error instanceof Error ? error.message : String(error),
    });

    return {
      result: duplicate ? "duplicate" : "failed",
      sourceFilePath: file.filePath,
      packageName: metadata?.packageName,
      versionCode: metadata?.versionCode,
      versionName: metadata?.versionName,
      displayName: metadata?.displayName,
      archivePath: archivePath ? path.relative(env.APK_STORAGE_DIR, archivePath) : undefined,
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}

async function resolveAutomationActor(): Promise<AuthenticatedRequestUser> {
  const preferredEmail = process.env.SEED_ADMIN_EMAIL?.trim() || "admin@empresa.local";
  const preferredUsername = process.env.SEED_ADMIN_USERNAME?.trim() || "admin";
  const preferredActor = await prisma.user.findFirst({
    where: {
      status: "ACTIVE",
      OR: [{ email: preferredEmail }, { username: preferredUsername }],
      roles: {
        some: {
          role: {
            code: {
              in: ["SUPER_ADMIN", "ADMIN", "APP_ADMIN"],
            },
          },
        },
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

  const actorRecord =
    preferredActor ??
    (await prisma.user.findFirst({
      where: {
        status: "ACTIVE",
        roles: {
          some: {
            role: {
              code: {
                in: ["SUPER_ADMIN", "ADMIN", "APP_ADMIN"],
              },
            },
          },
        },
      },
      orderBy: {
        createdAt: "asc",
      },
      include: {
        roles: {
          include: {
            role: true,
          },
        },
      },
    }));

  if (!actorRecord) {
    throw new ApiError(
      500,
      "Automatic APK import requires an active admin user. Run the seed or create an ADMIN.",
    );
  }

  return {
    userId: actorRecord.id,
    email: actorRecord.email,
    username: actorRecord.username,
    roles: actorRecord.roles.map((entry) => entry.role.code),
    sessionVersion: actorRecord.sessionVersion,
    passwordMustChange: actorRecord.passwordMustChange,
  };
}

async function ensureTargetApp(
  metadata: Awaited<ReturnType<typeof readApkManifestMetadata>>,
  actor: AuthenticatedRequestUser,
): Promise<{
  app: {
    id: string;
    slug: string;
    displayName: string;
    status: string;
    requiresExplicitAccess: boolean;
  };
  created: boolean;
}> {
  const existingApp = await prisma.app.findUnique({
    where: {
      packageName: metadata.packageName,
    },
    select: {
      id: true,
      slug: true,
      displayName: true,
      status: true,
      requiresExplicitAccess: true,
    },
  });

  if (existingApp) {
    return {
      app: existingApp,
      created: false,
    };
  }

  const displayName =
    metadata.displayName?.trim() || humanizePackageSegment(metadata.packageName.split(".").at(-1) ?? "app");
  const slug = await resolveUniqueSlug(buildDefaultSlug(displayName, metadata.packageName));
  const app = await createApp(
    {
      packageName: metadata.packageName,
      slug,
      displayName,
      shortDescription: `Aplicacion corporativa importada automaticamente desde ${metadata.packageName}.`,
      description:
        "Registro creado por el importador automatico de APKs. Ajusta la descripcion desde el flujo administrativo si necesitas texto mas especifico.",
      category: "internal",
      requiresExplicitAccess: false,
      status: "DRAFT",
    },
    actor,
  );

  return {
    app: {
      id: app.id,
      slug: app.slug,
      displayName: app.displayName,
      status: app.status,
      requiresExplicitAccess: app.requiresExplicitAccess,
    },
    created: true,
  };
}

async function resolveUniqueSlug(baseSlug: string): Promise<string> {
  let candidate = baseSlug || `app-${Date.now()}`;
  let suffix = 2;

  while (
    await prisma.app.findUnique({
      where: {
        slug: candidate,
      },
      select: {
        id: true,
      },
    })
  ) {
    candidate = `${baseSlug}-${suffix}`;
    suffix += 1;
  }

  return candidate;
}

function buildDefaultSlug(displayName: string, packageName: string): string {
  const displaySlug = slugify(displayName);
  const packageSlug = slugify(packageName.replace(/\./g, "-"));
  return [displaySlug, packageSlug].filter(Boolean).join("-").slice(0, 140);
}

function humanizePackageSegment(value: string): string {
  return value
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function buildImportedChangelog(): string {
  return `Version importada automaticamente desde la carpeta apks el ${new Date().toISOString()}.`;
}

function buildArchivedFileName(originalFileName: string): string {
  const extension = path.extname(originalFileName).toLowerCase() || ".apk";
  const fileStem = slugify(path.basename(originalFileName, path.extname(originalFileName))) || "apk";
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `${timestamp}-${fileStem}${extension}`;
}

async function archiveUnprocessedFile(
  currentFilePath: string,
  destinationDirectory: string,
): Promise<string | null> {
  try {
    return await moveFileToDirectory(
      currentFilePath,
      destinationDirectory,
      path.basename(currentFilePath),
    );
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return null;
    }

    throw error;
  }
}

async function writeImportFailureReport(
  archivedFilePath: string | null,
  payload: Record<string, unknown>,
): Promise<void> {
  const targetDirectory = archivedFilePath
    ? path.dirname(archivedFilePath)
    : path.join(env.APK_STORAGE_DIR, FAILED_DIRECTORY_NAME);
  const reportFileName = archivedFilePath
    ? `${path.basename(archivedFilePath)}.json`
    : `${buildArchivedFileName("apk-import-error")}.json`;

  await ensureDirectory(targetDirectory);
  await writeFile(
    path.join(targetDirectory, reportFileName),
    `${JSON.stringify(payload, null, 2)}\n`,
    "utf8",
  );
}

async function rollbackAutoCreatedApp(appId: string): Promise<void> {
  const versionCount = await prisma.appVersion.count({
    where: {
      appId,
    },
  });

  if (versionCount > 0) {
    return;
  }

  await prisma.app.delete({
    where: {
      id: appId,
    },
  });
}

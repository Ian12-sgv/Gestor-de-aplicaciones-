import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { access, open, stat, type FileHandle } from "node:fs/promises";
import path from "node:path";
import { ApiError } from "./api-error";

const APK_CONTENT_TYPES = new Set<string>([
  "application/vnd.android.package-archive",
  "application/octet-stream",
  "application/zip",
  "binary/octet-stream",
]);

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const MAX_EOCD_SEARCH = 65535 + 22;

export type ApkInspectionResult = {
  sha256: string;
  fileSizeBytes: bigint;
  contentType: string | null;
  fileExtension: string;
  archiveEntryCount: number;
  originalFileName: string | null;
};

export function normalizeRelativeStoragePath(value: string): string {
  return value.replace(/\\/g, "/").replace(/^\/+/, "");
}

export function resolveStoredApkPath(
  storageRoot: string,
  apkPath: string,
): { filePath: string; relativePath: string } | null {
  const normalizedPath = normalizeRelativeStoragePath(apkPath);
  const filePath = path.resolve(storageRoot, normalizedPath);
  const relativePath = path.relative(storageRoot, filePath);

  if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
    return null;
  }

  return {
    filePath,
    relativePath: normalizeRelativeStoragePath(relativePath),
  };
}

export async function storedApkExists(storageRoot: string, apkPath: string): Promise<boolean> {
  const resolvedPath = resolveStoredApkPath(storageRoot, apkPath);

  if (!resolvedPath) {
    return false;
  }

  try {
    await access(resolvedPath.filePath);
    return true;
  } catch {
    return false;
  }
}

export async function inspectApkFile(
  filePath: string,
  options?: {
    declaredFileName?: string | null;
    contentType?: string | null;
    expectedSha256?: string | null;
  },
): Promise<ApkInspectionResult> {
  const declaredFileName = options?.declaredFileName?.trim() || path.basename(filePath);
  const contentType = normalizeContentType(options?.contentType);
  const expectedSha256 = normalizeSha256(options?.expectedSha256);
  const fileExtension = validateApkExtension(declaredFileName);
  let fileStats;

  try {
    fileStats = await stat(filePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      throw new ApiError(404, "The referenced APK file does not exist.");
    }

    throw error;
  }

  if (!fileStats.isFile() || fileStats.size <= 0) {
    throw new ApiError(400, "The APK file is empty or unavailable.");
  }

  if (contentType !== null && !APK_CONTENT_TYPES.has(contentType)) {
    throw new ApiError(
      400,
      "The uploaded file content type is not allowed for APK files.",
      { contentType },
    );
  }

  const entryNames = await readZipEntryNames(filePath);
  const hasAndroidManifest = entryNames.includes("AndroidManifest.xml");
  const hasClassesDex = entryNames.some((entryName) =>
    /^classes(\d+)?\.dex$/i.test(path.posix.basename(entryName)),
  );

  if (!hasAndroidManifest || !hasClassesDex) {
    throw new ApiError(
      400,
      "The uploaded file is not a valid Android APK archive.",
      {
        hasAndroidManifest,
        hasClassesDex,
      },
    );
  }

  const sha256 = await computeSha256(filePath);

  if (expectedSha256 !== null && expectedSha256 !== sha256) {
    throw new ApiError(400, "The provided sha256 does not match the APK content.");
  }

  return {
    sha256,
    fileSizeBytes: BigInt(fileStats.size),
    contentType,
    fileExtension,
    archiveEntryCount: entryNames.length,
    originalFileName: declaredFileName || null,
  };
}

async function computeSha256(filePath: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const hash = createHash("sha256");
    const stream = createReadStream(filePath);

    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("error", (error) => {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") {
        reject(new ApiError(404, "The referenced APK file does not exist."));
        return;
      }

      reject(error);
    });
    stream.on("end", () => resolve(hash.digest("hex")));
  });
}

async function readZipEntryNames(filePath: string): Promise<string[]> {
  let handle: FileHandle;

  try {
    handle = await open(filePath, "r");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      throw new ApiError(404, "The referenced APK file does not exist.");
    }

    throw error;
  }

  try {
    const fileStats = await handle.stat();

    if (fileStats.size < 22) {
      throw new ApiError(400, "The uploaded APK is incomplete or corrupt.");
    }

    const tailSize = Math.min(fileStats.size, MAX_EOCD_SEARCH);
    const tailBuffer = Buffer.alloc(tailSize);
    await handle.read(tailBuffer, 0, tailSize, fileStats.size - tailSize);

    let eocdOffset = -1;

    for (let index = tailBuffer.length - 22; index >= 0; index -= 1) {
      if (tailBuffer.readUInt32LE(index) === EOCD_SIGNATURE) {
        eocdOffset = index;
        break;
      }
    }

    if (eocdOffset < 0) {
      throw new ApiError(400, "The uploaded APK is not a valid ZIP archive.");
    }

    const centralDirectorySize = tailBuffer.readUInt32LE(eocdOffset + 12);
    const centralDirectoryOffset = tailBuffer.readUInt32LE(eocdOffset + 16);

    if (centralDirectorySize === 0xffffffff || centralDirectoryOffset === 0xffffffff) {
      throw new ApiError(400, "ZIP64 APK archives are not supported by this backend.");
    }

    if (centralDirectorySize <= 0) {
      throw new ApiError(400, "The uploaded APK does not contain a readable central directory.");
    }

    const centralDirectory = Buffer.alloc(centralDirectorySize);
    await handle.read(centralDirectory, 0, centralDirectorySize, centralDirectoryOffset);

    const entryNames: string[] = [];
    let offset = 0;

    while (offset + 46 <= centralDirectory.length) {
      if (centralDirectory.readUInt32LE(offset) !== CENTRAL_DIRECTORY_SIGNATURE) {
        throw new ApiError(400, "The uploaded APK contains a corrupted ZIP directory.");
      }

      const fileNameLength = centralDirectory.readUInt16LE(offset + 28);
      const extraFieldLength = centralDirectory.readUInt16LE(offset + 30);
      const commentLength = centralDirectory.readUInt16LE(offset + 32);
      const recordLength = 46 + fileNameLength + extraFieldLength + commentLength;

      if (offset + recordLength > centralDirectory.length) {
        throw new ApiError(400, "The uploaded APK contains truncated ZIP metadata.");
      }

      entryNames.push(
        centralDirectory.toString("utf8", offset + 46, offset + 46 + fileNameLength),
      );

      offset += recordLength;
    }

    if (entryNames.length === 0) {
      throw new ApiError(400, "The uploaded APK archive does not contain readable entries.");
    }

    return entryNames;
  } finally {
    await handle.close();
  }
}

function validateApkExtension(fileName: string): string {
  const extension = path.extname(fileName).toLowerCase();

  if (extension !== ".apk") {
    throw new ApiError(400, "The uploaded file must use the .apk extension.");
  }

  return extension.slice(1);
}

function normalizeContentType(value: string | null | undefined): string | null {
  const normalizedValue = value?.trim().toLowerCase();
  return normalizedValue ? normalizedValue : null;
}

function normalizeSha256(value: string | null | undefined): string | null {
  const normalizedValue = value?.trim().toLowerCase();
  return normalizedValue ? normalizedValue : null;
}

import { execFile } from "node:child_process";
import { access, readdir } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { ApiError } from "./api-error";
import { readBinaryManifestMetadata } from "./apk-binary-manifest";

const execFileAsync = promisify(execFile);
const aaptExecutableName = process.platform === "win32" ? "aapt.exe" : "aapt";

export type ApkManifestMetadata = {
  packageName: string;
  versionCode: number;
  versionName: string;
  displayName: string | null;
  aaptPath: string;
};

export async function readApkManifestMetadata(filePath: string): Promise<ApkManifestMetadata> {
  try {
    return await readApkManifestMetadataWithAapt(filePath);
  } catch (aaptError) {
    if (!(aaptError instanceof ApiError) || aaptError.statusCode < 500) {
      throw aaptError;
    }

    // aapt is not installed (or failed); fall back to the built-in binary manifest reader.
    try {
      const metadata = await readBinaryManifestMetadata(filePath);
      return {
        packageName: metadata.packageName,
        versionCode: metadata.versionCode,
        versionName: metadata.versionName || String(metadata.versionCode),
        displayName: null,
        aaptPath: "builtin",
      };
    } catch (parserError) {
      throw new ApiError(400, "The file is not a readable Android APK.", {
        aapt: aaptError.message,
        parser: parserError instanceof Error ? parserError.message : String(parserError),
      });
    }
  }
}

async function readApkManifestMetadataWithAapt(filePath: string): Promise<ApkManifestMetadata> {
  const aaptPath = await resolveAaptPath();
  let stdout: string;

  try {
    const result = await execFileAsync(aaptPath, ["dump", "badging", filePath], {
      windowsHide: true,
      timeout: 30_000,
      maxBuffer: 10 * 1024 * 1024,
    });
    stdout = result.stdout;
  } catch (error) {
    throw new ApiError(
      500,
      "Unable to extract Android manifest metadata from the APK. Verify aapt or ANDROID_AAPT_PATH.",
      {
        aaptPath,
        filePath,
        error: error instanceof Error ? error.message : String(error),
      },
    );
  }

  const lines = stdout.split(/\r?\n/);
  const packageLine = lines.find((line) => line.startsWith("package:"));

  if (!packageLine) {
    throw new ApiError(400, "The APK metadata output does not contain a package declaration.");
  }

  const packageName = extractQuotedField(packageLine, "name");
  const versionCodeRaw = extractQuotedField(packageLine, "versionCode");
  const versionName = extractQuotedField(packageLine, "versionName") ?? "";
  const versionCode = Number.parseInt(versionCodeRaw ?? "", 10);

  if (!packageName || !Number.isInteger(versionCode) || versionCode <= 0) {
    throw new ApiError(400, "The APK metadata output is missing packageName or versionCode.", {
      packageLine,
    });
  }

  const labelLine =
    lines.find((line) => /^application-label:'/.test(line)) ??
    lines.find((line) => /^application-label-[^:]+:'/.test(line)) ??
    null;

  return {
    packageName,
    versionCode,
    versionName: versionName || String(versionCode),
    displayName: extractLineValue(labelLine),
    aaptPath,
  };
}

async function resolveAaptPath(): Promise<string> {
  const explicitPath = process.env.ANDROID_AAPT_PATH?.trim();

  if (explicitPath) {
    await ensureFileExists(explicitPath);
    return explicitPath;
  }

  for (const candidate of await resolveSdkBuildToolsCandidates()) {
    if (await fileExists(candidate)) {
      return candidate;
    }
  }

  for (const candidate of resolvePathCandidates()) {
    if (await fileExists(candidate)) {
      return candidate;
    }
  }

  throw new ApiError(
    500,
    "Could not find aapt. Install Android build-tools or set ANDROID_AAPT_PATH.",
  );
}

async function resolveSdkBuildToolsCandidates(): Promise<string[]> {
  const sdkRoots = new Set<string>();
  const envSdkRoots = [
    process.env.ANDROID_SDK_ROOT,
    process.env.ANDROID_HOME,
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Android", "Sdk") : null,
    process.env.HOME ? path.join(process.env.HOME, "Android", "Sdk") : null,
    process.env.USERPROFILE ? path.join(process.env.USERPROFILE, "AppData", "Local", "Android", "Sdk") : null,
  ];

  for (const sdkRoot of envSdkRoots) {
    if (sdkRoot) {
      sdkRoots.add(path.resolve(sdkRoot));
    }
  }

  const candidates: string[] = [];

  for (const sdkRoot of sdkRoots) {
    const buildToolsDirectory = path.join(sdkRoot, "build-tools");
    let entries;

    try {
      entries = await readdir(buildToolsDirectory, { withFileTypes: true });
    } catch {
      continue;
    }

    const versions = entries
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort(compareBuildToolsVersions)
      .reverse();

    for (const version of versions) {
      candidates.push(path.join(buildToolsDirectory, version, aaptExecutableName));
    }
  }

  return candidates;
}

function resolvePathCandidates(): string[] {
  const candidates = new Set<string>();

  for (const segment of (process.env.PATH ?? "").split(path.delimiter)) {
    const trimmedSegment = segment.trim();

    if (!trimmedSegment) {
      continue;
    }

    candidates.add(path.join(trimmedSegment, aaptExecutableName));
  }

  return Array.from(candidates);
}

function compareBuildToolsVersions(left: string, right: string): number {
  const leftTokens = tokenizeVersion(left);
  const rightTokens = tokenizeVersion(right);
  const maxLength = Math.max(leftTokens.length, rightTokens.length);

  for (let index = 0; index < maxLength; index += 1) {
    const leftToken = leftTokens[index] ?? "";
    const rightToken = rightTokens[index] ?? "";
    const leftNumber = Number.parseInt(leftToken, 10);
    const rightNumber = Number.parseInt(rightToken, 10);
    const numbersComparable = Number.isFinite(leftNumber) && Number.isFinite(rightNumber);

    if (numbersComparable && leftNumber !== rightNumber) {
      return leftNumber - rightNumber;
    }

    if (!numbersComparable && leftToken !== rightToken) {
      return leftToken.localeCompare(rightToken);
    }
  }

  return left.localeCompare(right);
}

function tokenizeVersion(value: string): string[] {
  return value
    .split(/[^0-9A-Za-z]+/)
    .map((token) => token.trim())
    .filter(Boolean);
}

function extractQuotedField(line: string, fieldName: string): string | null {
  const match = line.match(new RegExp(`${fieldName}='([^']*)'`));
  return match?.[1] ?? null;
}

function extractLineValue(line: string | null): string | null {
  if (!line) {
    return null;
  }

  const match = line.match(/:'(.*)'$/);
  return match?.[1]?.trim() || null;
}

async function ensureFileExists(filePath: string): Promise<void> {
  if (!(await fileExists(filePath))) {
    throw new ApiError(500, "The configured ANDROID_AAPT_PATH does not exist.", { filePath });
  }
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

import { mkdir, rename, rm, unlink } from "node:fs/promises";
import path from "node:path";

export async function ensureDirectory(directoryPath: string): Promise<void> {
  await mkdir(directoryPath, { recursive: true });
}

export async function moveFileToDirectory(
  sourcePath: string,
  destinationDirectory: string,
  fileName: string,
): Promise<string> {
  await ensureDirectory(destinationDirectory);
  const destinationPath = path.join(destinationDirectory, fileName);
  await rename(sourcePath, destinationPath);
  return destinationPath;
}

export async function removeFileIfExists(filePath: string | null | undefined): Promise<void> {
  if (!filePath) {
    return;
  }

  try {
    await unlink(filePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      throw error;
    }
  }
}

export async function removeDirectoryIfExists(directoryPath: string | null | undefined): Promise<void> {
  if (!directoryPath) {
    return;
  }

  await rm(directoryPath, { recursive: true, force: true });
}

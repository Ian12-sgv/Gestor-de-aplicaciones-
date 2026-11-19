import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { ApiError } from "./api-error";

const mediaExtensions = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
} as const;

const managedIconPathPattern = /^icons\/[0-9a-f-]{36}\.(png|jpg|webp)$/;

export type SupportedImageContentType = keyof typeof mediaExtensions;

export function createIconRelativePath(contentType: SupportedImageContentType): string {
  return `icons/${randomUUID()}.${mediaExtensions[contentType]}`;
}

export function isManagedIconPath(relativePath: string | null): relativePath is string {
  return relativePath !== null && managedIconPathPattern.test(relativePath);
}

export function resolveStoredMediaPath(
  storageRoot: string,
  relativePath: string,
): { filePath: string; relativePath: string } | null {
  if (!isManagedIconPath(relativePath)) {
    return null;
  }

  const normalizedRoot = path.resolve(storageRoot);
  const filePath = path.resolve(normalizedRoot, relativePath);
  const relative = path.relative(normalizedRoot, filePath);

  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    return null;
  }

  return {
    filePath,
    relativePath: relative.split(path.sep).join("/"),
  };
}

export async function inspectUploadedImage(uploadedFile: Express.Multer.File): Promise<{
  contentType: SupportedImageContentType;
}> {
  const declaredContentType = uploadedFile.mimetype as SupportedImageContentType;

  if (!(declaredContentType in mediaExtensions)) {
    throw new ApiError(400, "Only PNG, JPEG and WebP images are allowed.");
  }

  const content = await readFile(uploadedFile.path);

  if (!hasMatchingImageSignature(content, declaredContentType)) {
    throw new ApiError(400, "The uploaded file does not match its declared image type.");
  }

  return { contentType: declaredContentType };
}

export function imageContentTypeForPath(relativePath: string): SupportedImageContentType | null {
  switch (path.extname(relativePath).toLowerCase()) {
    case ".png":
      return "image/png";
    case ".jpg":
      return "image/jpeg";
    case ".webp":
      return "image/webp";
    default:
      return null;
  }
}

function hasMatchingImageSignature(content: Buffer, contentType: SupportedImageContentType): boolean {
  if (contentType === "image/png") {
    return content.length >= 8 && content.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  }

  if (contentType === "image/jpeg") {
    return content.length >= 3 && content.subarray(0, 3).equals(Buffer.from([255, 216, 255]));
  }

  return (
    content.length >= 12 &&
    content.subarray(0, 4).equals(Buffer.from("RIFF")) &&
    content.subarray(8, 12).equals(Buffer.from("WEBP"))
  );
}

import fs from "node:fs";
import path from "node:path";
import multer from "multer";
import { env } from "../config/env";

const incomingDirectory = path.join(env.APK_STORAGE_DIR, ".incoming");
fs.mkdirSync(incomingDirectory, { recursive: true });

const mediaIncomingDirectory = path.join(env.MEDIA_STORAGE_DIR, ".incoming");
fs.mkdirSync(mediaIncomingDirectory, { recursive: true });

export const apkUpload = multer({
  dest: incomingDirectory,
  limits: {
    fileSize: 1024 * 1024 * 1024,
  },
});

export const appIconUpload = multer({
  dest: mediaIncomingDirectory,
  limits: {
    fileSize: 5 * 1024 * 1024,
    files: 1,
  },
});


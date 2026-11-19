import type { Request, Response } from "express";
import { asyncHandler } from "../../utils/async-handler";
import * as appsService from "./apps.service";

export const listAppsController = asyncHandler(async (req: Request, res: Response) => {
  const result = await appsService.listApps(req.user, req.query.deviceId as string | undefined);
  res.status(200).json({ items: result });
});

export const getAppController = asyncHandler(async (req: Request, res: Response) => {
  const result = await appsService.getAppById(
    req.params.id,
    req.user,
    req.query.deviceId as string | undefined,
  );
  res.status(200).json(result);
});

export const getAppIconController = asyncHandler(async (req: Request, res: Response) => {
  const icon = await appsService.getAppIcon(req.params.id, req.user);
  res.set("Cache-Control", "public, max-age=86400");
  res.type(icon.contentType).sendFile(icon.filePath);
});

export const getLatestVersionController = asyncHandler(async (req: Request, res: Response) => {
  const result = await appsService.getLatestVersion(
    req.params.id,
    req.user,
    req.query.deviceId as string | undefined,
  );
  res.status(200).json(result);
});

export const getChangelogController = asyncHandler(async (req: Request, res: Response) => {
  const result = await appsService.getChangelog(req.params.id, req.user);
  res.status(200).json(result);
});

export const downloadAppController = asyncHandler(async (req: Request, res: Response) => {
  const result = await appsService.prepareDownload(req.params.id, req.user, {
    deviceId: req.query.deviceId as string | undefined,
    versionCode: req.query.versionCode as number | undefined,
  });

  res.download(result.filePath, result.fileName);
});

export const downloadPdbStoreController = asyncHandler(async (_req: Request, res: Response) => {
  const result = await appsService.preparePdbStoreDownload();
  res.set("Cache-Control", "no-store");
  res.set("Content-Type", "application/vnd.android.package-archive");
  res.download(result.filePath, result.fileName);
});


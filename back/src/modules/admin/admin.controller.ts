import type { Request, Response } from "express";
import { asyncHandler } from "../../utils/async-handler";
import * as adminService from "./admin.service";
import type { ListInstallationLogsQuery } from "./admin.schemas";

function serializeVersion(version: {
  fileSizeBytes: bigint | null;
  [key: string]: unknown;
}) {
  return {
    ...version,
    fileSizeBytes: version.fileSizeBytes?.toString() ?? null,
  };
}

export const createAppController = asyncHandler(async (req: Request, res: Response) => {
  const app = await adminService.createApp(req.body, req.user!);
  res.status(201).json({ app });
});

export const createUserController = asyncHandler(async (req: Request, res: Response) => {
  const user = await adminService.createUser(req.body);
  res.status(201).json({ user });
});

export const createAppVersionController = asyncHandler(async (req: Request, res: Response) => {
  const version = await adminService.createAppVersion(req.params.id, req.body, req.file, req.user!);
  res.status(201).json({
    version: serializeVersion(version),
  });
});

export const updateAppStatusController = asyncHandler(async (req: Request, res: Response) => {
  const app = await adminService.updateAppStatus(req.params.id, req.body);
  res.status(200).json({ app });
});

export const deleteAppFromStoreController = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.deleteAppFromStore(req.params.id, req.user!);
  res.status(200).json({ result });
});

export const updateVersionMandatoryController = asyncHandler(async (req: Request, res: Response) => {
  const version = await adminService.updateVersionMandatory(req.params.id, req.body);
  res.status(200).json({ version: serializeVersion(version) });
});

export const upsertAppUserAccessController = asyncHandler(async (req: Request, res: Response) => {
  const permission = await adminService.upsertAppUserAccess(
    req.params.id,
    req.params.userId,
    req.body,
  );
  res.status(200).json({ permission });
});

export const upsertAppRoleAccessController = asyncHandler(async (req: Request, res: Response) => {
  const permission = await adminService.upsertAppRoleAccess(
    req.params.id,
    req.params.roleCode,
    req.body,
  );
  res.status(200).json({ permission });
});

export const listInstallationLogsController = asyncHandler(async (req: Request, res: Response) => {
  const items = await adminService.listInstallationLogs(req.query as unknown as ListInstallationLogsQuery);
  res.status(200).json({ items });
});

export const revokeUserAccessController = asyncHandler(async (req: Request, res: Response) => {
  const result = await adminService.revokeUserAccess(req.params.id, req.body, req.user!);
  res.status(200).json({ result });
});

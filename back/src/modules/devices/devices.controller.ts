import type { Request, Response } from "express";
import { asyncHandler } from "../../utils/async-handler";
import * as devicesService from "./devices.service";

export const registerDeviceController = asyncHandler(async (req: Request, res: Response) => {
  const device = await devicesService.registerDevice(req.body, req.user!);
  res.status(201).json({ device });
});

export const reportInstallationController = asyncHandler(async (req: Request, res: Response) => {
  const result = await devicesService.reportInstallation(req.body, req.user!);
  res.status(200).json(result);
});


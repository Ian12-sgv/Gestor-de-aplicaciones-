import type { Request, Response } from "express";
import { resolveClientIp } from "../../middlewares/rate-limit";
import { asyncHandler } from "../../utils/async-handler";
import * as authService from "./auth.service";

function getRequestMetadata(req: Request) {
  return {
    ipAddress: resolveClientIp(req),
    userAgent: req.get("user-agent") ?? null,
  };
}

export const loginController = asyncHandler(async (req: Request, res: Response) => {
  const result = await authService.login(req.body, getRequestMetadata(req));
  res.status(200).json(result);
});

export const refreshController = asyncHandler(async (req: Request, res: Response) => {
  const result = await authService.refreshSession(req.body, getRequestMetadata(req));
  res.status(200).json(result);
});

export const logoutController = asyncHandler(async (req: Request, res: Response) => {
  await authService.logout(req.body);
  res.status(204).send();
});

export const changePasswordController = asyncHandler(async (req: Request, res: Response) => {
  const user = await authService.changePassword(req.user!.userId, req.body);
  res.status(200).json({ user });
});

export const meController = asyncHandler(async (req: Request, res: Response) => {
  const user = await authService.getCurrentUser(req.user!.userId);
  res.status(200).json({ user });
});

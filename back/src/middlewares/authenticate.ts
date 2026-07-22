import type { NextFunction, Request, Response } from "express";
import { hydrateAuthenticatedUser } from "../modules/auth/auth.service";
import { ApiError } from "../utils/api-error";
import { verifyAccessToken } from "../utils/jwt";

export async function authenticate(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  const authorizationHeader = req.headers.authorization;

  if (!authorizationHeader?.startsWith("Bearer ")) {
    next(new ApiError(401, "Authentication required"));
    return;
  }

  const token = authorizationHeader.slice("Bearer ".length).trim();

  try {
    const tokenUser = verifyAccessToken(token);
    req.user = await hydrateAuthenticatedUser(tokenUser);
    next();
  } catch (error) {
    if (error instanceof ApiError) {
      next(error);
      return;
    }

    next(new ApiError(401, "Invalid or expired access token"));
  }
}

export function requirePasswordReady(
  req: Request,
  _res: Response,
  next: NextFunction,
): void {
  if (!req.user) {
    next(new ApiError(401, "Authentication required"));
    return;
  }

  if (req.user.passwordMustChange) {
    next(new ApiError(403, "Password change required", { code: "PASSWORD_CHANGE_REQUIRED" }));
    return;
  }

  next();
}

import type { NextFunction, Request, Response } from "express";
import { hasAnyPermission, hasRole, type PermissionCode } from "../config/domain";
import { ApiError } from "../utils/api-error";

export function authorizeRoles(allowedRoles: readonly string[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      next(new ApiError(401, "Authentication required"));
      return;
    }

    if (!hasRole(req.user.roles, allowedRoles)) {
      next(new ApiError(403, "Insufficient permissions"));
      return;
    }

    next();
  };
}

export function authorizePermissions(allowedPermissions: readonly PermissionCode[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      next(new ApiError(401, "Authentication required"));
      return;
    }

    if (!hasAnyPermission(req.user.roles, allowedPermissions)) {
      next(new ApiError(403, "Insufficient permissions"));
      return;
    }

    next();
  };
}

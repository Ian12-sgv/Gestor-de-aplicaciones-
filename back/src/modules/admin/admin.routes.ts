import { Router } from "express";
import { PERMISSIONS } from "../../config/domain";
import { authorizePermissions } from "../../middlewares/authorize";
import { apkUpload } from "../../middlewares/upload";
import { validate } from "../../middlewares/validate";
import {
  createAppController,
  createAppVersionController,
  createUserController,
  deleteAppFromStoreController,
  listInstallationLogsController,
  revokeUserAccessController,
  upsertAppRoleAccessController,
  upsertAppUserAccessController,
  updateAppStatusController,
  updateVersionMandatoryController,
} from "./admin.controller";
import {
  appRoleParamsSchema,
  appUserParamsSchema,
  appParamsSchema,
  createUserSchema,
  createAppSchema,
  createAppVersionSchema,
  listInstallationLogsQuerySchema,
  revokeUserAccessSchema,
  updateAppStatusSchema,
  updateVersionMandatorySchema,
  upsertAppUserAccessSchema,
  userParamsSchema,
  versionParamsSchema,
} from "./admin.schemas";

const router = Router();

router.post(
  "/users",
  authorizePermissions([PERMISSIONS.USER_CREATE]),
  validate(createUserSchema),
  createUserController,
);
router.post(
  "/apps",
  authorizePermissions([PERMISSIONS.APP_CREATE]),
  validate(createAppSchema),
  createAppController,
);
router.post(
  "/apps/:id/versions",
  authorizePermissions([PERMISSIONS.APP_VERSION_CREATE]),
  apkUpload.single("apkFile"),
  validate(appParamsSchema, "params"),
  validate(createAppVersionSchema),
  createAppVersionController,
);
router.patch(
  "/apps/:id/status",
  authorizePermissions([PERMISSIONS.APP_STATUS_UPDATE]),
  validate(appParamsSchema, "params"),
  validate(updateAppStatusSchema),
  updateAppStatusController,
);
router.delete(
  "/apps/:id",
  authorizePermissions([PERMISSIONS.APP_DELETE]),
  validate(appParamsSchema, "params"),
  deleteAppFromStoreController,
);
router.put(
  "/apps/:id/users/:userId/access",
  authorizePermissions([PERMISSIONS.APP_ACCESS_MANAGE]),
  validate(appUserParamsSchema, "params"),
  validate(upsertAppUserAccessSchema),
  upsertAppUserAccessController,
);
router.put(
  "/apps/:id/roles/:roleCode/access",
  authorizePermissions([PERMISSIONS.APP_ACCESS_MANAGE]),
  validate(appRoleParamsSchema, "params"),
  validate(upsertAppUserAccessSchema),
  upsertAppRoleAccessController,
);
router.patch(
  "/versions/:id/mandatory",
  authorizePermissions([PERMISSIONS.APP_VERSION_MANDATORY_UPDATE]),
  validate(versionParamsSchema, "params"),
  validate(updateVersionMandatorySchema),
  updateVersionMandatoryController,
);
router.post(
  "/users/:id/revoke-access",
  authorizePermissions([PERMISSIONS.USER_REVOKE]),
  validate(userParamsSchema, "params"),
  validate(revokeUserAccessSchema),
  revokeUserAccessController,
);
router.get(
  "/installation-logs",
  authorizePermissions([PERMISSIONS.AUDIT_LOG_READ]),
  validate(listInstallationLogsQuerySchema, "query"),
  listInstallationLogsController,
);

export const adminRoutes = router;

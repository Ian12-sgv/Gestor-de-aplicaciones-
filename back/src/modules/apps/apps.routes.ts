import { Router } from "express";
import { validate } from "../../middlewares/validate";
import {
  appDetailQuerySchema,
  appIdParamsSchema,
  appsListQuerySchema,
  downloadQuerySchema,
} from "./apps.schemas";
import {
  downloadAppController,
  getAppController,
  getChangelogController,
  getAppIconController,
  getLatestVersionController,
  listAppsController,
} from "./apps.controller";

const router = Router();

router.get("/", validate(appsListQuerySchema, "query"), listAppsController);
router.get("/:id/icon", validate(appIdParamsSchema, "params"), getAppIconController);
router.get("/:id", validate(appIdParamsSchema, "params"), validate(appDetailQuerySchema, "query"), getAppController);
router.get("/:id/latest-version", validate(appIdParamsSchema, "params"), validate(appDetailQuerySchema, "query"), getLatestVersionController);
router.get("/:id/changelog", validate(appIdParamsSchema, "params"), getChangelogController);
router.get("/:id/download", validate(appIdParamsSchema, "params"), validate(downloadQuerySchema, "query"), downloadAppController);

export const appsRoutes = router;

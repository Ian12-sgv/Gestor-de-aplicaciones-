import { Router } from "express";
import { validate } from "../../middlewares/validate";
import {
  registerDeviceController,
  reportInstallationController,
} from "./devices.controller";
import { registerDeviceSchema, reportInstallationSchema } from "./devices.schemas";

const router = Router();

router.post("/register", validate(registerDeviceSchema), registerDeviceController);
router.post("/report-installation", validate(reportInstallationSchema), reportInstallationController);

export const devicesRoutes = router;

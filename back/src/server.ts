import { app } from "./app";
import { env } from "./config/env";
import { prisma } from "./config/prisma";
import { ApkAutoImportWorker } from "./modules/admin/apk-auto-import";
import { logError, logInfo, logWarn } from "./utils/logger";

const apkAutoImportWorker = env.APK_AUTO_IMPORT_ENABLED ? new ApkAutoImportWorker() : null;
const server = app.listen(env.PORT, env.HOST, () => {
  logInfo("server.started", {
    host: env.HOST,
    port: env.PORT,
    environment: env.NODE_ENV,
    configSource: env.CONFIG_SOURCE,
  });

  apkAutoImportWorker?.start();
});

async function shutdown(signal: string) {
  logWarn("server.shutdown_requested", { signal });
  server.close(async () => {
    try {
      await apkAutoImportWorker?.stop();
      await prisma.$disconnect();
      logInfo("server.stopped", { signal });
      process.exit(0);
    } catch (error) {
      logError("server.shutdown_failed", {
        signal,
        error: error instanceof Error ? error.message : String(error),
      });
      process.exit(1);
    }
  });
}

process.on("SIGINT", () => {
  void shutdown("SIGINT");
});

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});

import { prisma } from "../config/prisma";
import { runApkAutoImportOnce } from "../modules/admin/apk-auto-import";

async function main() {
  const summary = await runApkAutoImportOnce();
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

void main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

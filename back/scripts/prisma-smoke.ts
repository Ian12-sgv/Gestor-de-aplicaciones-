import { prisma } from "../src/config/prisma";

async function main() {
  const timestamp = Date.now();
  const packageName = `com.company.prisma.smoke.${timestamp}`;
  const slug = `prisma-smoke-${timestamp}`;

  const databaseInfo = await prisma.$queryRawUnsafe<
    Array<{ database_name: string; server_version: string }>
  >(
    "SELECT DB_NAME() AS database_name, @@VERSION AS server_version",
  );

  const countsBefore = {
    roles: await prisma.role.count(),
    users: await prisma.user.count(),
    apps: await prisma.app.count(),
  };

  const smokeApp = await prisma.app.create({
    data: {
      packageName,
      slug,
      displayName: "Prisma Smoke Validation",
      shortDescription: "Temporary app to validate Prisma write access.",
      description: "Created and deleted by back/scripts/prisma-smoke.ts.",
      category: "ops",
      status: "DRAFT",
      requiresExplicitAccess: true,
    },
    select: {
      id: true,
      packageName: true,
      slug: true,
      createdAt: true,
    },
  });

  await prisma.app.delete({
    where: {
      id: smokeApp.id,
    },
  });

  const countsAfter = {
    roles: await prisma.role.count(),
    users: await prisma.user.count(),
    apps: await prisma.app.count(),
  };

  console.log(
    JSON.stringify(
      {
        database: databaseInfo[0] ?? null,
        countsBefore,
        countsAfter,
        smokeApp,
        writeDeleteRoundTripOk: countsBefore.apps === countsAfter.apps,
      },
      null,
      2,
    ),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

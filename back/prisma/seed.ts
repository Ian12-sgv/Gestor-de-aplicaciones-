import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { hashPassword } from "../src/utils/password";

const prisma = new PrismaClient();

const roleDefinitions = [
  {
    code: "SUPER_ADMIN",
    name: "Super Administrador",
    description: "Control total del portal corporativo de aplicaciones.",
  },
  {
    code: "ADMIN",
    name: "Administrador",
    description: "Gestiona catalogo, versiones y accesos administrativos.",
  },
  {
    code: "APP_ADMIN",
    name: "Administrador de Apps",
    description: "Publica apps y versiones asignadas dentro del portal.",
  },
  {
    code: "EMPLOYEE",
    name: "Empleado",
    description: "Usuario final autorizado para ver, descargar y actualizar apps corporativas.",
  },
] as const;

const seedAdmin = {
  email: process.env.SEED_ADMIN_EMAIL ?? "admin@empresa.local",
  username: process.env.SEED_ADMIN_USERNAME ?? "sistema",
  password: process.env.SEED_ADMIN_PASSWORD ?? "",
  firstName: process.env.SEED_ADMIN_FIRST_NAME ?? "Admin",
  lastName: process.env.SEED_ADMIN_LAST_NAME ?? "Inicial",
};

function validateSeedAdmin() {
  if (!seedAdmin.password || seedAdmin.password === "CHANGE_ME") {
    throw new Error("SEED_ADMIN_PASSWORD is required: set it in back/.env before running the seed");
  }

  if (seedAdmin.password.length < 8) {
    throw new Error("SEED_ADMIN_PASSWORD must contain at least 8 characters");
  }
}

async function seedRoles() {
  for (const role of roleDefinitions) {
    await prisma.role.upsert({
      where: { code: role.code },
      update: {
        name: role.name,
        description: role.description,
      },
      create: {
        code: role.code,
        name: role.name,
        description: role.description,
      },
    });
  }
}

async function seedAdminUser() {
  const existingUsers = await prisma.user.findMany({
    where: {
      OR: [{ email: seedAdmin.email }, { username: seedAdmin.username }],
    },
    select: {
      id: true,
      email: true,
      username: true,
    },
  });

  if (existingUsers.length > 1) {
    throw new Error(
      "Found multiple users matching the seed admin email/username. Review existing data before seeding the admin user.",
    );
  }

  const passwordHash = await hashPassword(seedAdmin.password);

  const user = existingUsers[0]
    ? await prisma.user.update({
        where: { id: existingUsers[0].id },
        data: {
          email: seedAdmin.email,
          username: seedAdmin.username,
          passwordHash,
          firstName: seedAdmin.firstName,
          lastName: seedAdmin.lastName,
          status: "ACTIVE",
          passwordMustChange: false,
        },
      })
    : await prisma.user.create({
        data: {
          email: seedAdmin.email,
          username: seedAdmin.username,
          passwordHash,
          firstName: seedAdmin.firstName,
          lastName: seedAdmin.lastName,
          status: "ACTIVE",
          passwordMustChange: false,
        },
      });

  const superAdminRole = await prisma.role.findUniqueOrThrow({
    where: { code: "SUPER_ADMIN" },
  });

  await prisma.userRole.upsert({
    where: {
      userId_roleId: {
        userId: user.id,
        roleId: superAdminRole.id,
      },
    },
    update: {},
    create: {
      userId: user.id,
      roleId: superAdminRole.id,
    },
  });

  return user;
}

async function main() {
  validateSeedAdmin();
  await seedRoles();
  const adminUser = await seedAdminUser();

  console.log("Seed completed successfully.");
  console.log(`Roles seeded: ${roleDefinitions.map((role) => role.code).join(", ")}`);
  console.log(`Admin user: ${adminUser.email} (${adminUser.username})`);
  console.log("Assigned role: SUPER_ADMIN");
}

main()
  .catch((error) => {
    console.error("Seed failed.", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

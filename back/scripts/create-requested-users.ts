import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { hashPassword } from "../src/utils/password";

const prisma = new PrismaClient();

const usersToCreate = [
  {
    email: "admin.usuario@empresa.local",
    username: "admin",
    password: "j2094l,.",
    firstName: "Admin",
    lastName: "Usuario",
    roleCode: "ADMIN",
  },
  {
    previousUsername: "jefe",
    email: "inventario@empresa.local",
    username: "inventario",
    password: "123456",
    firstName: "Inventario",
    lastName: "Usuario",
    roleCode: "EMPLOYEE",
  },
  {
    email: "tienda@empresa.local",
    username: "tienda",
    password: "789456",
    firstName: "Tienda",
    lastName: "Usuario",
    roleCode: "EMPLOYEE",
  },
] as const;

const roleDefinitions = {
  ADMIN: {
    name: "Administrador",
    description: "Gestiona catalogo, versiones y accesos administrativos.",
  },
  EMPLOYEE: {
    name: "Empleado",
    description: "Usuario final autorizado para ver, descargar y actualizar apps corporativas.",
  },
} as const;

async function ensureRole(roleCode: keyof typeof roleDefinitions) {
  const role = roleDefinitions[roleCode];

  return prisma.role.upsert({
    where: { code: roleCode },
    update: {
      name: role.name,
      description: role.description,
    },
    create: {
      code: roleCode,
      name: role.name,
      description: role.description,
    },
  });
}

async function upsertUser(userInput: (typeof usersToCreate)[number]) {
  const role = await ensureRole(userInput.roleCode);
  const passwordHash = await hashPassword(userInput.password);
  const existingUser = await prisma.user.findFirst({
    where: {
      OR: [
        { username: userInput.username },
        { email: userInput.email },
        ...("previousUsername" in userInput
          ? [{ username: userInput.previousUsername }]
          : []),
      ],
    },
    select: {
      id: true,
    },
  });

  const user = existingUser
    ? await prisma.user.update({
        where: { id: existingUser.id },
        data: {
          email: userInput.email,
          username: userInput.username,
          passwordHash,
          firstName: userInput.firstName,
          lastName: userInput.lastName,
          status: "ACTIVE",
          passwordMustChange: false,
        },
      })
    : await prisma.user.create({
        data: {
          email: userInput.email,
          username: userInput.username,
          passwordHash,
          firstName: userInput.firstName,
          lastName: userInput.lastName,
          status: "ACTIVE",
          passwordMustChange: false,
        },
      });

  await prisma.userRole.upsert({
    where: {
      userId_roleId: {
        userId: user.id,
        roleId: role.id,
      },
    },
    update: {},
    create: {
      userId: user.id,
      roleId: role.id,
    },
  });

  return {
    id: user.id,
    email: user.email,
    username: user.username,
    role: role.code,
  };
}

async function main() {
  const createdUsers = [];

  for (const userInput of usersToCreate) {
    createdUsers.push(await upsertUser(userInput));
  }

  console.log("Users created or updated:");
  for (const user of createdUsers) {
    console.log(`- ${user.username} (${user.email}) role=${user.role}`);
  }
}

main()
  .catch((error) => {
    console.error("Failed to create requested users.", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

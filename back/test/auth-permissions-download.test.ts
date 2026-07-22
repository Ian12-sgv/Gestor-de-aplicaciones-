import { randomUUID } from "node:crypto";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import type { Server } from "node:http";
import { app } from "../src/app";
import { env } from "../src/config/env";
import { prisma } from "../src/config/prisma";
import { hashPassword } from "../src/utils/password";

const runId = randomUUID().replace(/-/g, "");
const testPackageName = `com.company.test.${runId}`;
const restrictedPackageName = `com.company.restricted.${runId}`;
const visibleNoInstallPackageName = `com.company.visible.${runId}`;
const testStorageRelativeDir = `test-suite/${runId}`;
const testApkRelativePath = `${testStorageRelativeDir}/public-app.apk`;
const testApkBody = "fake apk content for protected download test";

let server: Server;
let baseUrl: string;
let employeeUserId: string;
let publicAppId: string;
let visibleNoInstallAppId: string;
let visibleNoInstallVersionCode: number;
let employeeAccessToken: string;
let employeeRefreshToken: string;

before(async () => {
  server = await listenOnRandomPort();
  baseUrl = resolveBaseUrl(server);
  await seedTestData();
});

after(async () => {
  await cleanupTestData();
  await new Promise<void>((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
  await prisma.$disconnect();
});

describe("backend auth, permissions and download", () => {
  test("login rejects invalid credentials and accepts a valid employee", async () => {
    const invalidLogin = await postJson("/api/auth/login", {
      identifier: `employee-${runId}`,
      password: "wrong-password",
    });

    assert.equal(invalidLogin.status, 401);

    const validLogin = await postJson("/api/auth/login", {
      identifier: `employee-${runId}`,
      password: "Employee123!",
    });
    const body = await validLogin.json() as {
      accessToken?: string;
      refreshToken?: string;
      user?: { username?: string; roles?: string[]; passwordMustChange?: boolean };
    };

    assert.equal(validLogin.status, 200);
    assert.equal(body.user?.username, `employee-${runId}`);
    assert.deepEqual(body.user?.roles, ["EMPLOYEE"]);
    assert.equal(body.user?.passwordMustChange, true);
    assert.ok(body.accessToken);
    assert.ok(body.refreshToken);

    employeeAccessToken = body.accessToken!;
    employeeRefreshToken = body.refreshToken!;
  });

  test("change password enforces policy and clears the initial-change flag", async () => {
    const weakPasswordResponse = await postJson(
      "/api/auth/change-password",
      {
        currentPassword: "Employee123!",
        newPassword: "123456",
      },
      employeeAccessToken,
    );

    assert.equal(weakPasswordResponse.status, 400);

    const blockedCatalogResponse = await getJson("/api/apps", employeeAccessToken);
    const blockedCatalogBody = await blockedCatalogResponse.json() as {
      details?: { code?: string };
    };

    assert.equal(blockedCatalogResponse.status, 403);
    assert.equal(blockedCatalogBody.details?.code, "PASSWORD_CHANGE_REQUIRED");

    const changePasswordResponse = await postJson(
      "/api/auth/change-password",
      {
        currentPassword: "Employee123!",
        newPassword: "FreshPass123!",
      },
      employeeAccessToken,
    );
    const body = await changePasswordResponse.json() as {
      user?: { passwordMustChange?: boolean; passwordChangedAt?: string };
    };

    assert.equal(changePasswordResponse.status, 200);
    assert.equal(body.user?.passwordMustChange, false);
    assert.ok(body.user?.passwordChangedAt);
  });

  test("refresh rotates an employee session token", async () => {
    const refreshResponse = await postJson("/api/auth/refresh", {
      refreshToken: employeeRefreshToken,
    });
    const body = await refreshResponse.json() as {
      accessToken?: string;
      refreshToken?: string;
    };

    assert.equal(refreshResponse.status, 200);
    assert.ok(body.accessToken);
    assert.ok(body.refreshToken);
    assert.notEqual(body.refreshToken, employeeRefreshToken);

    employeeAccessToken = body.accessToken!;
    employeeRefreshToken = body.refreshToken!;
  });

  test("catalog permissions hide restricted apps and show explicit view-only apps", async () => {
    const catalogResponse = await getJson("/api/apps", employeeAccessToken);
    const body = await catalogResponse.json() as {
      items?: Array<{ id: string; packageName: string }>;
    };

    assert.equal(catalogResponse.status, 200);
    assert.ok(body.items?.some((item) => item.packageName === testPackageName));
    assert.ok(body.items?.some((item) => item.packageName === visibleNoInstallPackageName));
    assert.ok(!body.items?.some((item) => item.packageName === restrictedPackageName));
  });

  test("download requires install permission and serves an allowed app", async () => {
    const forbiddenDownload = await fetch(
      `${baseUrl}/api/apps/${visibleNoInstallAppId}/download?versionCode=${visibleNoInstallVersionCode}`,
      {
        headers: {
          Authorization: `Bearer ${employeeAccessToken}`,
        },
      },
    );

    assert.equal(forbiddenDownload.status, 404);

    const allowedDownload = await fetch(`${baseUrl}/api/apps/${publicAppId}/download`, {
      headers: {
        Authorization: `Bearer ${employeeAccessToken}`,
      },
    });
    const body = Buffer.from(await allowedDownload.arrayBuffer()).toString("utf8");

    assert.equal(allowedDownload.status, 200);
    assert.match(allowedDownload.headers.get("content-disposition") ?? "", /attachment/);
    assert.equal(body, testApkBody);

    const downloadLog = await prisma.installationLog.findFirst({
      where: {
        appId: publicAppId,
        userId: employeeUserId,
        action: "DOWNLOAD",
        status: "SUCCESS",
      },
    });

    assert.ok(downloadLog);
  });
});

async function listenOnRandomPort(): Promise<Server> {
  return new Promise((resolve, reject) => {
    const testServer = app.listen(0, "127.0.0.1", () => resolve(testServer));
    testServer.once("error", reject);
  });
}

function resolveBaseUrl(testServer: Server): string {
  const address = testServer.address();

  if (!address || typeof address === "string") {
    throw new Error("Unable to resolve test server address");
  }

  return `http://127.0.0.1:${address.port}`;
}

async function seedTestData(): Promise<void> {
  const employeeRole = await prisma.role.upsert({
    where: { code: "EMPLOYEE" },
    update: {
      name: "Empleado",
      description: "Usuario final autorizado para ver, descargar y actualizar apps corporativas.",
    },
    create: {
      code: "EMPLOYEE",
      name: "Empleado",
      description: "Usuario final autorizado para ver, descargar y actualizar apps corporativas.",
    },
  });
  const passwordHash = await hashPassword("Employee123!");
  const employee = await prisma.user.create({
    data: {
      email: `employee-${runId}@empresa.local`,
      username: `employee-${runId}`,
      passwordHash,
      firstName: "Employee",
      lastName: "Test",
      status: "ACTIVE",
      passwordMustChange: true,
      roles: {
        create: {
          roleId: employeeRole.id,
        },
      },
    },
  });
  employeeUserId = employee.id;

  const apkFilePath = path.join(env.APK_STORAGE_DIR, testApkRelativePath);
  await mkdir(path.dirname(apkFilePath), { recursive: true });
  await writeFile(apkFilePath, testApkBody, "utf8");

  const publicApp = await createTestApp({
    packageName: testPackageName,
    slug: `test-public-${runId}`,
    displayName: `Test Public ${runId}`,
    requiresExplicitAccess: false,
    apkPath: testApkRelativePath,
    versionCode: 1001,
  });
  publicAppId = publicApp.id;

  await createTestApp({
    packageName: restrictedPackageName,
    slug: `test-restricted-${runId}`,
    displayName: `Test Restricted ${runId}`,
    requiresExplicitAccess: true,
    apkPath: testApkRelativePath,
    versionCode: 1002,
  });

  const visibleNoInstallApp = await createTestApp({
    packageName: visibleNoInstallPackageName,
    slug: `test-visible-${runId}`,
    displayName: `Test Visible ${runId}`,
    requiresExplicitAccess: true,
    apkPath: testApkRelativePath,
    versionCode: 1003,
  });
  visibleNoInstallAppId = visibleNoInstallApp.id;
  visibleNoInstallVersionCode = visibleNoInstallApp.versionCode;

  await prisma.appUserPermission.create({
    data: {
      appId: visibleNoInstallApp.id,
      userId: employeeUserId,
      canView: true,
      canInstall: false,
    },
  });
}

async function createTestApp(input: {
  packageName: string;
  slug: string;
  displayName: string;
  requiresExplicitAccess: boolean;
  apkPath: string;
  versionCode: number;
}): Promise<{ id: string; versionCode: number }> {
  const appRecord = await prisma.app.create({
    data: {
      packageName: input.packageName,
      slug: input.slug,
      displayName: input.displayName,
      shortDescription: "Integration test app",
      description: "Integration test app",
      status: "ACTIVE",
      requiresExplicitAccess: input.requiresExplicitAccess,
      versions: {
        create: {
          versionName: "1.0.0",
          versionCode: input.versionCode,
          apkPath: input.apkPath,
          originalFileName: "public-app.apk",
          contentType: "application/vnd.android.package-archive",
          fileExtension: "apk",
          fileSizeBytes: BigInt(testApkBody.length),
          sha256: null,
        },
      },
    },
  });

  return {
    id: appRecord.id,
    versionCode: input.versionCode,
  };
}

async function cleanupTestData(): Promise<void> {
  const appIds = (
    await prisma.app.findMany({
      where: {
        packageName: {
          in: [testPackageName, restrictedPackageName, visibleNoInstallPackageName],
        },
      },
      select: {
        id: true,
      },
    })
  ).map((record) => record.id);

  await prisma.installationLog.deleteMany({
    where: {
      OR: [{ appId: { in: appIds } }, { userId: employeeUserId }],
    },
  });
  await prisma.deviceAppState.deleteMany({ where: { appId: { in: appIds } } });
  await prisma.appUserPermission.deleteMany({ where: { appId: { in: appIds } } });
  await prisma.appRolePermission.deleteMany({ where: { appId: { in: appIds } } });
  await prisma.appVersion.deleteMany({ where: { appId: { in: appIds } } });
  await prisma.app.deleteMany({ where: { id: { in: appIds } } });
  await prisma.refreshToken.deleteMany({ where: { userId: employeeUserId } });
  await prisma.userRole.deleteMany({ where: { userId: employeeUserId } });
  await prisma.user.deleteMany({ where: { id: employeeUserId } });
  await rm(path.join(env.APK_STORAGE_DIR, testStorageRelativeDir), {
    recursive: true,
    force: true,
  });
}

async function postJson(
  pathname: string,
  payload: Record<string, unknown>,
  accessToken?: string,
): Promise<Response> {
  return fetch(`${baseUrl}${pathname}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: JSON.stringify(payload),
  });
}

async function getJson(pathname: string, accessToken: string): Promise<Response> {
  return fetch(`${baseUrl}${pathname}`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
}

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "email" VARCHAR(320) NOT NULL,
    "username" VARCHAR(100) NOT NULL,
    "passwordHash" VARCHAR(255) NOT NULL,
    "firstName" VARCHAR(100),
    "lastName" VARCHAR(100),
    "status" VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Role" (
    "id" UUID NOT NULL,
    "code" VARCHAR(50) NOT NULL,
    "name" VARCHAR(100) NOT NULL,
    "description" VARCHAR(500),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Role_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserRole" (
    "userId" UUID NOT NULL,
    "roleId" UUID NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserRole_pkey" PRIMARY KEY ("userId","roleId")
);

-- CreateTable
CREATE TABLE "Device" (
    "id" UUID NOT NULL,
    "userId" UUID,
    "deviceIdentifier" VARCHAR(191) NOT NULL,
    "name" VARCHAR(150) NOT NULL,
    "platform" VARCHAR(30) NOT NULL DEFAULT 'ANDROID',
    "manufacturer" VARCHAR(120),
    "model" VARCHAR(120),
    "osVersion" VARCHAR(50),
    "appVersionName" VARCHAR(60),
    "pushToken" VARCHAR(255),
    "status" VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    "lastSeenAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Device_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "App" (
    "id" UUID NOT NULL,
    "packageName" VARCHAR(255) NOT NULL,
    "slug" VARCHAR(150) NOT NULL,
    "displayName" VARCHAR(150) NOT NULL,
    "shortDescription" VARCHAR(300),
    "description" TEXT,
    "iconPath" VARCHAR(500),
    "bannerPath" VARCHAR(500),
    "category" VARCHAR(100),
    "status" VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    "requiresExplicitAccess" BOOLEAN NOT NULL DEFAULT false,
    "createdById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "App_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppVersion" (
    "id" UUID NOT NULL,
    "appId" UUID NOT NULL,
    "versionName" VARCHAR(60) NOT NULL,
    "versionCode" INTEGER NOT NULL,
    "changelog" TEXT,
    "apkPath" VARCHAR(500) NOT NULL,
    "fileSizeBytes" BIGINT,
    "sha256" VARCHAR(128),
    "minSupportedVersionCode" INTEGER,
    "isMandatory" BOOLEAN NOT NULL DEFAULT false,
    "createdById" UUID,
    "releasedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppVersion_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DeviceAppState" (
    "id" UUID NOT NULL,
    "deviceId" UUID NOT NULL,
    "appId" UUID NOT NULL,
    "installedVersionId" UUID,
    "installedVersionCode" INTEGER,
    "installedVersionName" VARCHAR(60),
    "status" VARCHAR(30) NOT NULL DEFAULT 'UNKNOWN',
    "lastReportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastOpenedAt" TIMESTAMP(3),
    "notes" VARCHAR(500),

    CONSTRAINT "DeviceAppState_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppUserPermission" (
    "id" UUID NOT NULL,
    "appId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "canView" BOOLEAN NOT NULL DEFAULT true,
    "canInstall" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppUserPermission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppRolePermission" (
    "id" UUID NOT NULL,
    "appId" UUID NOT NULL,
    "roleId" UUID NOT NULL,
    "canView" BOOLEAN NOT NULL DEFAULT true,
    "canInstall" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AppRolePermission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InstallationLog" (
    "id" UUID NOT NULL,
    "appId" UUID NOT NULL,
    "appVersionId" UUID,
    "deviceId" UUID,
    "userId" UUID,
    "action" VARCHAR(30) NOT NULL,
    "status" VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    "installedVersionCode" INTEGER,
    "requestedVersionCode" INTEGER,
    "details" VARCHAR(1000),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InstallationLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE INDEX "User_status_idx" ON "User"("status");

-- CreateIndex
CREATE UNIQUE INDEX "Role_code_key" ON "Role"("code");

-- CreateIndex
CREATE UNIQUE INDEX "Device_deviceIdentifier_key" ON "Device"("deviceIdentifier");

-- CreateIndex
CREATE INDEX "Device_userId_idx" ON "Device"("userId");

-- CreateIndex
CREATE INDEX "Device_status_idx" ON "Device"("status");

-- CreateIndex
CREATE UNIQUE INDEX "App_packageName_key" ON "App"("packageName");

-- CreateIndex
CREATE UNIQUE INDEX "App_slug_key" ON "App"("slug");

-- CreateIndex
CREATE INDEX "App_status_idx" ON "App"("status");

-- CreateIndex
CREATE INDEX "AppVersion_appId_releasedAt_idx" ON "AppVersion"("appId", "releasedAt");

-- CreateIndex
CREATE UNIQUE INDEX "AppVersion_appId_versionCode_key" ON "AppVersion"("appId", "versionCode");

-- CreateIndex
CREATE INDEX "DeviceAppState_appId_idx" ON "DeviceAppState"("appId");

-- CreateIndex
CREATE UNIQUE INDEX "DeviceAppState_deviceId_appId_key" ON "DeviceAppState"("deviceId", "appId");

-- CreateIndex
CREATE UNIQUE INDEX "AppUserPermission_appId_userId_key" ON "AppUserPermission"("appId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "AppRolePermission_appId_roleId_key" ON "AppRolePermission"("appId", "roleId");

-- CreateIndex
CREATE INDEX "InstallationLog_appId_createdAt_idx" ON "InstallationLog"("appId", "createdAt");

-- CreateIndex
CREATE INDEX "InstallationLog_deviceId_createdAt_idx" ON "InstallationLog"("deviceId", "createdAt");

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "Role"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "Device" ADD CONSTRAINT "Device_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "App" ADD CONSTRAINT "App_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppVersion" ADD CONSTRAINT "AppVersion_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppVersion" ADD CONSTRAINT "AppVersion_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "DeviceAppState" ADD CONSTRAINT "DeviceAppState_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "DeviceAppState" ADD CONSTRAINT "DeviceAppState_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "DeviceAppState" ADD CONSTRAINT "DeviceAppState_installedVersionId_fkey" FOREIGN KEY ("installedVersionId") REFERENCES "AppVersion"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppUserPermission" ADD CONSTRAINT "AppUserPermission_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppUserPermission" ADD CONSTRAINT "AppUserPermission_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppRolePermission" ADD CONSTRAINT "AppRolePermission_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "AppRolePermission" ADD CONSTRAINT "AppRolePermission_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "Role"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "InstallationLog" ADD CONSTRAINT "InstallationLog_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "InstallationLog" ADD CONSTRAINT "InstallationLog_appVersionId_fkey" FOREIGN KEY ("appVersionId") REFERENCES "AppVersion"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "InstallationLog" ADD CONSTRAINT "InstallationLog_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "Device"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "InstallationLog" ADD CONSTRAINT "InstallationLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

BEGIN TRY

BEGIN TRAN;

-- CreateSchema
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'dbo') EXEC sp_executesql N'CREATE SCHEMA [dbo];';

-- CreateTable
CREATE TABLE [dbo].[User] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [email] VARCHAR(320) NOT NULL,
    [username] VARCHAR(100) NOT NULL,
    [passwordHash] VARCHAR(255) NOT NULL,
    [passwordMustChange] BIT NOT NULL CONSTRAINT [User_passwordMustChange_df] DEFAULT 0,
    [passwordChangedAt] DATETIME2,
    [firstName] VARCHAR(100),
    [lastName] VARCHAR(100),
    [status] VARCHAR(30) NOT NULL CONSTRAINT [User_status_df] DEFAULT 'ACTIVE',
    [sessionVersion] INT NOT NULL CONSTRAINT [User_sessionVersion_df] DEFAULT 0,
    [lastLoginAt] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [User_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [User_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [User_email_key] UNIQUE NONCLUSTERED ([email]),
    CONSTRAINT [User_username_key] UNIQUE NONCLUSTERED ([username])
);

-- CreateTable
CREATE TABLE [dbo].[Role] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [code] VARCHAR(50) NOT NULL,
    [name] VARCHAR(100) NOT NULL,
    [description] VARCHAR(500),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Role_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Role_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Role_code_key] UNIQUE NONCLUSTERED ([code])
);

-- CreateTable
CREATE TABLE [dbo].[UserRole] (
    [userId] UNIQUEIDENTIFIER NOT NULL,
    [roleId] UNIQUEIDENTIFIER NOT NULL,
    [assignedAt] DATETIME2 NOT NULL CONSTRAINT [UserRole_assignedAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [UserRole_pkey] PRIMARY KEY CLUSTERED ([userId],[roleId])
);

-- CreateTable
CREATE TABLE [dbo].[Device] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [userId] UNIQUEIDENTIFIER,
    [deviceIdentifier] VARCHAR(191) NOT NULL,
    [name] VARCHAR(150) NOT NULL,
    [platform] VARCHAR(30) NOT NULL CONSTRAINT [Device_platform_df] DEFAULT 'ANDROID',
    [manufacturer] VARCHAR(120),
    [model] VARCHAR(120),
    [osVersion] VARCHAR(50),
    [appVersionName] VARCHAR(60),
    [pushToken] VARCHAR(255),
    [status] VARCHAR(30) NOT NULL CONSTRAINT [Device_status_df] DEFAULT 'ACTIVE',
    [lastSeenAt] DATETIME2,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [Device_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [Device_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [Device_deviceIdentifier_key] UNIQUE NONCLUSTERED ([deviceIdentifier])
);

-- CreateTable
CREATE TABLE [dbo].[App] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [packageName] VARCHAR(255) NOT NULL,
    [slug] VARCHAR(150) NOT NULL,
    [displayName] VARCHAR(150) NOT NULL,
    [shortDescription] VARCHAR(300),
    [description] TEXT,
    [iconPath] VARCHAR(500),
    [bannerPath] VARCHAR(500),
    [category] VARCHAR(100),
    [status] VARCHAR(30) NOT NULL CONSTRAINT [App_status_df] DEFAULT 'DRAFT',
    [requiresExplicitAccess] BIT NOT NULL CONSTRAINT [App_requiresExplicitAccess_df] DEFAULT 0,
    [createdById] UNIQUEIDENTIFIER,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [App_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [App_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [App_packageName_key] UNIQUE NONCLUSTERED ([packageName]),
    CONSTRAINT [App_slug_key] UNIQUE NONCLUSTERED ([slug])
);

-- CreateTable
CREATE TABLE [dbo].[AppVersion] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [appId] UNIQUEIDENTIFIER NOT NULL,
    [versionName] VARCHAR(60) NOT NULL,
    [versionCode] INT NOT NULL,
    [changelog] TEXT,
    [apkPath] VARCHAR(500) NOT NULL,
    [originalFileName] VARCHAR(255),
    [contentType] VARCHAR(120),
    [fileExtension] VARCHAR(20),
    [archiveEntryCount] INT,
    [fileSizeBytes] BIGINT,
    [sha256] VARCHAR(128),
    [minSupportedVersionCode] INT,
    [isMandatory] BIT NOT NULL CONSTRAINT [AppVersion_isMandatory_df] DEFAULT 0,
    [createdById] UNIQUEIDENTIFIER,
    [releasedAt] DATETIME2 NOT NULL CONSTRAINT [AppVersion_releasedAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AppVersion_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [AppVersion_appId_versionCode_key] UNIQUE NONCLUSTERED ([appId],[versionCode])
);

-- CreateTable
CREATE TABLE [dbo].[DeviceAppState] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [deviceId] UNIQUEIDENTIFIER NOT NULL,
    [appId] UNIQUEIDENTIFIER NOT NULL,
    [installedVersionId] UNIQUEIDENTIFIER,
    [installedVersionCode] INT,
    [installedVersionName] VARCHAR(60),
    [status] VARCHAR(30) NOT NULL CONSTRAINT [DeviceAppState_status_df] DEFAULT 'UNKNOWN',
    [lastReportedAt] DATETIME2 NOT NULL CONSTRAINT [DeviceAppState_lastReportedAt_df] DEFAULT CURRENT_TIMESTAMP,
    [lastOpenedAt] DATETIME2,
    [notes] VARCHAR(500),
    CONSTRAINT [DeviceAppState_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [DeviceAppState_deviceId_appId_key] UNIQUE NONCLUSTERED ([deviceId],[appId])
);

-- CreateTable
CREATE TABLE [dbo].[AppUserPermission] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [appId] UNIQUEIDENTIFIER NOT NULL,
    [userId] UNIQUEIDENTIFIER NOT NULL,
    [canView] BIT NOT NULL CONSTRAINT [AppUserPermission_canView_df] DEFAULT 1,
    [canInstall] BIT NOT NULL CONSTRAINT [AppUserPermission_canInstall_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AppUserPermission_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AppUserPermission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [AppUserPermission_appId_userId_key] UNIQUE NONCLUSTERED ([appId],[userId])
);

-- CreateTable
CREATE TABLE [dbo].[AppRolePermission] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [appId] UNIQUEIDENTIFIER NOT NULL,
    [roleId] UNIQUEIDENTIFIER NOT NULL,
    [canView] BIT NOT NULL CONSTRAINT [AppRolePermission_canView_df] DEFAULT 1,
    [canInstall] BIT NOT NULL CONSTRAINT [AppRolePermission_canInstall_df] DEFAULT 1,
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [AppRolePermission_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [AppRolePermission_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [AppRolePermission_appId_roleId_key] UNIQUE NONCLUSTERED ([appId],[roleId])
);

-- CreateTable
CREATE TABLE [dbo].[InstallationLog] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [appId] UNIQUEIDENTIFIER NOT NULL,
    [appVersionId] UNIQUEIDENTIFIER,
    [deviceId] UNIQUEIDENTIFIER,
    [userId] UNIQUEIDENTIFIER,
    [action] VARCHAR(30) NOT NULL,
    [status] VARCHAR(30) NOT NULL CONSTRAINT [InstallationLog_status_df] DEFAULT 'PENDING',
    [installedVersionCode] INT,
    [requestedVersionCode] INT,
    [details] VARCHAR(1000),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [InstallationLog_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT [InstallationLog_pkey] PRIMARY KEY CLUSTERED ([id])
);

-- CreateTable
CREATE TABLE [dbo].[RefreshToken] (
    [id] UNIQUEIDENTIFIER NOT NULL,
    [userId] UNIQUEIDENTIFIER NOT NULL,
    [tokenHash] VARCHAR(128) NOT NULL,
    [sessionVersion] INT NOT NULL,
    [expiresAt] DATETIME2 NOT NULL,
    [revokedAt] DATETIME2,
    [lastUsedAt] DATETIME2,
    [ipAddress] VARCHAR(64),
    [userAgent] VARCHAR(255),
    [createdAt] DATETIME2 NOT NULL CONSTRAINT [RefreshToken_createdAt_df] DEFAULT CURRENT_TIMESTAMP,
    [updatedAt] DATETIME2 NOT NULL,
    CONSTRAINT [RefreshToken_pkey] PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT [RefreshToken_tokenHash_key] UNIQUE NONCLUSTERED ([tokenHash])
);

-- CreateIndex
CREATE NONCLUSTERED INDEX [User_status_idx] ON [dbo].[User]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Device_userId_idx] ON [dbo].[Device]([userId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [Device_status_idx] ON [dbo].[Device]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [App_status_idx] ON [dbo].[App]([status]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [AppVersion_appId_releasedAt_idx] ON [dbo].[AppVersion]([appId], [releasedAt]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [DeviceAppState_appId_idx] ON [dbo].[DeviceAppState]([appId]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [InstallationLog_appId_createdAt_idx] ON [dbo].[InstallationLog]([appId], [createdAt]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [InstallationLog_deviceId_createdAt_idx] ON [dbo].[InstallationLog]([deviceId], [createdAt]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [RefreshToken_userId_expiresAt_idx] ON [dbo].[RefreshToken]([userId], [expiresAt]);

-- CreateIndex
CREATE NONCLUSTERED INDEX [RefreshToken_expiresAt_idx] ON [dbo].[RefreshToken]([expiresAt]);

-- AddForeignKey
ALTER TABLE [dbo].[UserRole] ADD CONSTRAINT [UserRole_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[UserRole] ADD CONSTRAINT [UserRole_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[Device] ADD CONSTRAINT [Device_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[App] ADD CONSTRAINT [App_createdById_fkey] FOREIGN KEY ([createdById]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppVersion] ADD CONSTRAINT [AppVersion_appId_fkey] FOREIGN KEY ([appId]) REFERENCES [dbo].[App]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppVersion] ADD CONSTRAINT [AppVersion_createdById_fkey] FOREIGN KEY ([createdById]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DeviceAppState] ADD CONSTRAINT [DeviceAppState_deviceId_fkey] FOREIGN KEY ([deviceId]) REFERENCES [dbo].[Device]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DeviceAppState] ADD CONSTRAINT [DeviceAppState_appId_fkey] FOREIGN KEY ([appId]) REFERENCES [dbo].[App]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[DeviceAppState] ADD CONSTRAINT [DeviceAppState_installedVersionId_fkey] FOREIGN KEY ([installedVersionId]) REFERENCES [dbo].[AppVersion]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppUserPermission] ADD CONSTRAINT [AppUserPermission_appId_fkey] FOREIGN KEY ([appId]) REFERENCES [dbo].[App]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppUserPermission] ADD CONSTRAINT [AppUserPermission_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppRolePermission] ADD CONSTRAINT [AppRolePermission_appId_fkey] FOREIGN KEY ([appId]) REFERENCES [dbo].[App]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[AppRolePermission] ADD CONSTRAINT [AppRolePermission_roleId_fkey] FOREIGN KEY ([roleId]) REFERENCES [dbo].[Role]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[InstallationLog] ADD CONSTRAINT [InstallationLog_appId_fkey] FOREIGN KEY ([appId]) REFERENCES [dbo].[App]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[InstallationLog] ADD CONSTRAINT [InstallationLog_appVersionId_fkey] FOREIGN KEY ([appVersionId]) REFERENCES [dbo].[AppVersion]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[InstallationLog] ADD CONSTRAINT [InstallationLog_deviceId_fkey] FOREIGN KEY ([deviceId]) REFERENCES [dbo].[Device]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[InstallationLog] ADD CONSTRAINT [InstallationLog_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE [dbo].[RefreshToken] ADD CONSTRAINT [RefreshToken_userId_fkey] FOREIGN KEY ([userId]) REFERENCES [dbo].[User]([id]) ON DELETE NO ACTION ON UPDATE NO ACTION;

COMMIT TRAN;

END TRY
BEGIN CATCH

IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRAN;
END;
THROW

END CATCH

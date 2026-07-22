export const USER_STATUSES = ["ACTIVE", "DISABLED"] as const;
export const APP_STATUSES = ["DRAFT", "ACTIVE", "DISABLED", "ARCHIVED"] as const;
export const DEVICE_STATUSES = ["ACTIVE", "BLOCKED", "RETIRED"] as const;
export const INSTALLATION_ACTIONS = [
  "DOWNLOAD",
  "INSTALL",
  "UPDATE",
  "OPEN",
  "REMOVE",
] as const;
export const INSTALLATION_RESULT_STATUSES = ["PENDING", "SUCCESS", "FAILED"] as const;
export const DEVICE_APP_STATUSES = [
  "UNKNOWN",
  "NOT_INSTALLED",
  "INSTALLED",
  "INSTALL_FAILED",
] as const;
export const ROLE_CODES = ["SUPER_ADMIN", "ADMIN", "APP_ADMIN", "EMPLOYEE"] as const;
export const ADMIN_ROLE_CODES = ["ADMIN", "SUPER_ADMIN", "APP_ADMIN"] as const;

export const PERMISSIONS = {
  APP_CATALOG_BYPASS: "app.catalog.bypass",
  APP_CREATE: "app.create",
  APP_VERSION_CREATE: "app.version.create",
  APP_STATUS_UPDATE: "app.status.update",
  APP_DELETE: "app.delete",
  APP_ACCESS_MANAGE: "app.access.manage",
  APP_VERSION_MANDATORY_UPDATE: "app.version.mandatory.update",
  USER_CREATE: "user.create",
  USER_REVOKE: "user.revoke",
  AUDIT_LOG_READ: "audit.log.read",
  DEVICE_REPORT_ANY: "device.report.any",
} as const;

export type RoleCode = (typeof ROLE_CODES)[number];
export type PermissionCode = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

const ALL_PERMISSIONS = Object.values(PERMISSIONS);

export const ROLE_PERMISSIONS: Record<RoleCode, readonly PermissionCode[]> = {
  SUPER_ADMIN: ALL_PERMISSIONS,
  ADMIN: [
    PERMISSIONS.APP_CATALOG_BYPASS,
    PERMISSIONS.APP_CREATE,
    PERMISSIONS.APP_VERSION_CREATE,
    PERMISSIONS.APP_STATUS_UPDATE,
    PERMISSIONS.APP_ACCESS_MANAGE,
    PERMISSIONS.APP_VERSION_MANDATORY_UPDATE,
    PERMISSIONS.USER_CREATE,
    PERMISSIONS.USER_REVOKE,
    PERMISSIONS.AUDIT_LOG_READ,
    PERMISSIONS.DEVICE_REPORT_ANY,
  ],
  APP_ADMIN: [
    PERMISSIONS.APP_CATALOG_BYPASS,
    PERMISSIONS.APP_CREATE,
    PERMISSIONS.APP_VERSION_CREATE,
    PERMISSIONS.APP_STATUS_UPDATE,
    PERMISSIONS.APP_ACCESS_MANAGE,
    PERMISSIONS.APP_VERSION_MANDATORY_UPDATE,
  ],
  EMPLOYEE: [],
};

export function hasRole(userRoles: readonly string[], allowedRoles: readonly string[]): boolean {
  return userRoles.some((role) => allowedRoles.includes(role));
}

export function hasPermission(
  userRoles: readonly string[],
  permission: PermissionCode,
): boolean {
  return userRoles.some((role) =>
    ((ROLE_PERMISSIONS as Record<string, readonly PermissionCode[]>)[role] ?? []).includes(
      permission,
    ),
  );
}

export function hasAnyPermission(
  userRoles: readonly string[],
  permissions: readonly PermissionCode[],
): boolean {
  return permissions.some((permission) => hasPermission(userRoles, permission));
}

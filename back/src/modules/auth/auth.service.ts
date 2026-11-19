import { createHash, randomBytes } from "node:crypto";
import type { Prisma } from "@prisma/client";
import { ROLE_PERMISSIONS, type RoleCode } from "../../config/domain";
import { env } from "../../config/env";
import { prisma } from "../../config/prisma";
import { ApiError } from "../../utils/api-error";
import { signAccessToken } from "../../utils/jwt";
import { comparePassword, hashPassword, validatePasswordPolicy } from "../../utils/password";
import type {
  AuthenticatedRequestUser,
  AuthenticatedUserProfile,
  LoginResult,
} from "./auth.types";
import type {
  ChangePasswordInput,
  LoginInput,
  LogoutInput,
  RefreshSessionInput,
} from "./auth.schemas";

const REFRESH_TOKEN_BYTES = 48;

const userWithRolesInclude = {
  roles: {
    include: {
      role: true,
    },
  },
} satisfies Prisma.UserInclude;

type UserWithRoles = Prisma.UserGetPayload<{
  include: typeof userWithRolesInclude;
}>;

type RequestMetadata = {
  ipAddress?: string | null;
  userAgent?: string | null;
};

function toAuthenticatedRequestUser(user: UserWithRoles): AuthenticatedRequestUser {
  return {
    userId: user.id,
    email: user.email,
    username: user.username,
    roles: user.roles.map((entry) => entry.role.code),
    sessionVersion: user.sessionVersion,
    passwordMustChange: user.passwordMustChange,
  };
}

function toAuthenticatedUserProfile(user: UserWithRoles): AuthenticatedUserProfile {
  return {
    ...toAuthenticatedRequestUser(user),
    firstName: user.firstName ?? null,
    lastName: user.lastName ?? null,
    status: user.status,
    lastLoginAt: user.lastLoginAt ?? null,
    passwordChangedAt: user.passwordChangedAt ?? null,
    permissions: resolvePermissions(user.roles.map((entry) => entry.role.code)),
  };
}

function resolvePermissions(roleCodes: readonly string[]): string[] {
  const permissions = new Set<string>();

  for (const roleCode of roleCodes) {
    for (const permission of ROLE_PERMISSIONS[roleCode as RoleCode] ?? []) {
      permissions.add(permission);
    }
  }

  return [...permissions];
}

function generateRefreshToken(): string {
  return randomBytes(REFRESH_TOKEN_BYTES).toString("base64url");
}

function hashRefreshToken(refreshToken: string): string {
  return createHash("sha256").update(refreshToken).digest("hex");
}

function resolveRefreshTokenExpiry(): Date {
  return new Date(Date.now() + 1000 * 60 * 60 * 24 * env.REFRESH_TOKEN_TTL_DAYS);
}

async function findUserByIdentifier(identifier: string): Promise<UserWithRoles | null> {
  return prisma.user.findFirst({
    where: {
      OR: [{ email: identifier }, { username: identifier }],
    },
    include: userWithRolesInclude,
  });
}

async function findUserById(userId: string): Promise<UserWithRoles | null> {
  return prisma.user.findUnique({
    where: { id: userId },
    include: userWithRolesInclude,
  });
}

async function issueSessionTokens(
  user: UserWithRoles,
  metadata?: RequestMetadata,
): Promise<LoginResult> {
  const refreshToken = generateRefreshToken();
  const refreshTokenHash = hashRefreshToken(refreshToken);
  const tokenUser = toAuthenticatedRequestUser(user);

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash: refreshTokenHash,
      sessionVersion: user.sessionVersion,
      expiresAt: resolveRefreshTokenExpiry(),
      ipAddress: truncate(metadata?.ipAddress, 64),
      userAgent: truncate(metadata?.userAgent, 255),
    },
  });

  return {
    accessToken: signAccessToken(tokenUser),
    refreshToken,
    user: toAuthenticatedUserProfile(user),
  };
}

export async function login(input: LoginInput, metadata?: RequestMetadata): Promise<LoginResult> {
  const user = await findUserByIdentifier(input.identifier);

  if (!user) {
    throw new ApiError(401, "Invalid credentials");
  }

  if (user.status !== "ACTIVE") {
    throw new ApiError(403, "User account is not active");
  }

  const isPasswordValid = await comparePassword(input.password, user.passwordHash);

  if (!isPasswordValid) {
    throw new ApiError(401, "Invalid credentials");
  }

  const now = new Date();
  const updatedUser = await prisma.user.update({
    where: { id: user.id },
    data: { lastLoginAt: now },
    include: userWithRolesInclude,
  });

  await prisma.refreshToken.deleteMany({
    where: {
      userId: user.id,
      OR: [
        { expiresAt: { lt: now } },
        { revokedAt: { not: null } },
      ],
    },
  });

  return issueSessionTokens(updatedUser, metadata);
}

export async function refreshSession(
  input: RefreshSessionInput,
  metadata?: RequestMetadata,
): Promise<LoginResult> {
  const now = new Date();
  const existingToken = await prisma.refreshToken.findUnique({
    where: {
      tokenHash: hashRefreshToken(input.refreshToken),
    },
    include: {
      user: {
        include: userWithRolesInclude,
      },
    },
  });

  if (!existingToken || existingToken.revokedAt !== null || existingToken.expiresAt <= now) {
    throw new ApiError(401, "Refresh token is invalid or expired");
  }

  if (existingToken.user.status !== "ACTIVE") {
    throw new ApiError(403, "User account is not active");
  }

  if (existingToken.user.sessionVersion !== existingToken.sessionVersion) {
    await prisma.refreshToken.update({
      where: { id: existingToken.id },
      data: {
        revokedAt: now,
        lastUsedAt: now,
      },
    });

    throw new ApiError(401, "Refresh token has been revoked");
  }

  await prisma.refreshToken.update({
    where: { id: existingToken.id },
    data: {
      revokedAt: now,
      lastUsedAt: now,
    },
  });

  return issueSessionTokens(existingToken.user, metadata);
}

export async function logout(input: LogoutInput): Promise<void> {
  const refreshTokenHash = hashRefreshToken(input.refreshToken);

  await prisma.refreshToken.updateMany({
    where: {
      tokenHash: refreshTokenHash,
      revokedAt: null,
    },
    data: {
      revokedAt: new Date(),
      lastUsedAt: new Date(),
    },
  });
}

export async function changePassword(
  userId: string,
  input: ChangePasswordInput,
): Promise<AuthenticatedUserProfile> {
  const user = await findUserById(userId);

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  if (user.status !== "ACTIVE") {
    throw new ApiError(403, "User account is not active");
  }

  const isCurrentPasswordValid = await comparePassword(input.currentPassword, user.passwordHash);

  if (!isCurrentPasswordValid) {
    throw new ApiError(401, "Current password is invalid");
  }

  const isSamePassword = await comparePassword(input.newPassword, user.passwordHash);

  if (isSamePassword) {
    throw new ApiError(400, "New password must be different from the current password");
  }

  validatePasswordPolicy(input.newPassword, {
    username: user.username,
    email: user.email,
  });

  const updatedUser = await prisma.user.update({
    where: {
      id: user.id,
    },
    data: {
      passwordHash: await hashPassword(input.newPassword),
      passwordMustChange: false,
      passwordChangedAt: new Date(),
    },
    include: userWithRolesInclude,
  });

  return toAuthenticatedUserProfile(updatedUser);
}

export async function getCurrentUser(userId: string): Promise<AuthenticatedUserProfile> {
  const user = await findUserById(userId);

  if (!user) {
    throw new ApiError(404, "User not found");
  }

  if (user.status !== "ACTIVE") {
    throw new ApiError(403, "User account is not active");
  }

  return toAuthenticatedUserProfile(user);
}

export async function hydrateAuthenticatedUser(
  tokenUser: AuthenticatedRequestUser,
): Promise<AuthenticatedRequestUser> {
  const user = await findUserById(tokenUser.userId);

  if (!user) {
    throw new ApiError(401, "Authentication required");
  }

  if (user.status !== "ACTIVE") {
    throw new ApiError(403, "User account is not active");
  }

  if (user.sessionVersion !== tokenUser.sessionVersion) {
    throw new ApiError(401, "Access token has been revoked");
  }

  return toAuthenticatedRequestUser(user);
}

export async function revokeAllSessionsForUser(userId: string): Promise<void> {
  const now = new Date();
  const user = await prisma.user.update({
    where: { id: userId },
    data: {
      sessionVersion: {
        increment: 1,
      },
    },
    select: {
      id: true,
      sessionVersion: true,
    },
  });

  await prisma.refreshToken.updateMany({
    where: {
      userId: user.id,
      revokedAt: null,
    },
    data: {
      revokedAt: now,
      lastUsedAt: now,
    },
  });
}

function truncate(value: string | null | undefined, maxLength: number): string | null {
  if (!value) {
    return null;
  }

  return value.length <= maxLength ? value : value.slice(0, maxLength);
}

import jwt from "jsonwebtoken";
import { env } from "../config/env";
import type { AuthenticatedRequestUser } from "../modules/auth/auth.types";

export function signAccessToken(user: AuthenticatedRequestUser): string {
  return jwt.sign(user, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN as never,
  });
}

export function verifyAccessToken(token: string): AuthenticatedRequestUser {
  return jwt.verify(token, env.JWT_SECRET) as AuthenticatedRequestUser;
}

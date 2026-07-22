import { z } from "zod";

export const loginSchema = z.object({
  identifier: z.string().trim().min(3).max(320),
  password: z.string().min(1).max(128),
});

export const refreshSessionSchema = z.object({
  refreshToken: z.string().trim().min(40).max(512),
});

export const logoutSchema = z.object({
  refreshToken: z.string().trim().min(40).max(512),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: z.string().min(8).max(128),
});

export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshSessionInput = z.infer<typeof refreshSessionSchema>;
export type LogoutInput = z.infer<typeof logoutSchema>;
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>;

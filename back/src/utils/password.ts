import bcrypt from "bcrypt";
import { ApiError } from "./api-error";

const SALT_ROUNDS = 12;
const MIN_PASSWORD_LENGTH = 8;

export function hashPassword(value: string): Promise<string> {
  return bcrypt.hash(value, SALT_ROUNDS);
}

export function comparePassword(value: string, hash: string): Promise<boolean> {
  return bcrypt.compare(value, hash);
}

export function validatePasswordPolicy(value: string, options?: { username?: string; email?: string }): void {
  const errors: string[] = [];
  const normalizedValue = value.toLowerCase();
  const username = options?.username?.trim().toLowerCase();
  const emailLocalPart = options?.email?.split("@")[0]?.trim().toLowerCase();

  if (value.length < MIN_PASSWORD_LENGTH) {
    errors.push(`Debe tener al menos ${MIN_PASSWORD_LENGTH} caracteres.`);
  }

  if (!/[a-z]/.test(value)) {
    errors.push("Debe incluir una letra minuscula.");
  }

  if (!/[A-Z]/.test(value)) {
    errors.push("Debe incluir una letra mayuscula.");
  }

  if (!/\d/.test(value)) {
    errors.push("Debe incluir un numero.");
  }

  if (!/[^A-Za-z0-9]/.test(value)) {
    errors.push("Debe incluir un simbolo.");
  }

  if (username && normalizedValue.includes(username)) {
    errors.push("No debe contener el nombre de usuario.");
  }

  if (emailLocalPart && normalizedValue.includes(emailLocalPart)) {
    errors.push("No debe contener el correo.");
  }

  if (errors.length > 0) {
    throw new ApiError(400, "Password does not meet the minimum policy.", {
      errors,
    });
  }
}

import type { AuthenticatedRequestUser } from "../modules/auth/auth.types";

declare global {
  namespace Express {
    interface Request {
      requestId?: string;
      user?: AuthenticatedRequestUser;
    }
  }
}

export {};

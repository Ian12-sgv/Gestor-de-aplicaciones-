export interface AuthenticatedRequestUser {
  userId: string;
  email: string;
  username: string;
  roles: string[];
  sessionVersion: number;
  passwordMustChange: boolean;
}

export interface AuthenticatedUserProfile extends AuthenticatedRequestUser {
  firstName: string | null;
  lastName: string | null;
  status: string;
  lastLoginAt: Date | null;
  passwordChangedAt: Date | null;
}

export interface AuthSessionTokens {
  accessToken: string;
  refreshToken: string;
}

export interface LoginResult extends AuthSessionTokens {
  user: AuthenticatedUserProfile;
}

export interface AuthUser {
  id?: string;
  sub?: string;
  email?: string;
  role?: string;
  user_metadata?: { full_name?: string; role?: string };
  app_metadata?: { role?: string };
}

export interface AuthData {
  access_token: string;
  refresh_token?: string;
  user?: AuthUser;
  expiry: number;
}

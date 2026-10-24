"use client";

import { useAuth } from "@clerk/nextjs";
import { useRouter } from "next/navigation";
import { useCallback, useEffect } from "react";

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

export class UnauthorizedError extends Error {
  constructor() {
    super("Your session has ended. Please sign in again.");
  }
}

/**
 * For pages that need a signed-in user: sends signed-out visitors to /login and
 * returns a fetch that attaches the Clerk session token for the TrainWise API.
 */
export function useApi() {
  const { isLoaded, isSignedIn, getToken } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (isLoaded && !isSignedIn) router.replace("/login");
  }, [isLoaded, isSignedIn, router]);

  const apiFetch = useCallback(
    async (path: string, init: RequestInit = {}) => {
      const token = await getToken();
      if (!token) {
        router.replace("/login");
        throw new UnauthorizedError();
      }

      const headers = new Headers(init.headers);
      headers.set("Authorization", `Bearer ${token}`);
      const response = await fetch(`${API_URL}${path}`, { ...init, headers });

      if (response.status === 401) {
        router.replace("/login");
        throw new UnauthorizedError();
      }
      return response;
    },
    [getToken, router],
  );

  return { apiFetch, isReady: isLoaded && isSignedIn === true };
}

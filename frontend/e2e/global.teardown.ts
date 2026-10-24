import { test as teardown } from "@playwright/test";

// Deletes +clerk_test users from the Clerk development instance so test runs don't
// pile up users until the instance's user limit is reached. Only users older than
// an hour are deleted, so a run that is still in progress (another CI job, or a
// local run) keeps its users. A failed cleanup only logs a warning.
const CLERK_API = "https://api.clerk.com/v1";
const STALE_AFTER_MS = 60 * 60 * 1000;
const PAGE_SIZE = 100;

type ClerkUser = {
  id: string;
  created_at: number;
  email_addresses: { email_address: string }[];
};

teardown("delete stale Clerk test users", async () => {
  const secretKey = process.env.CLERK_SECRET_KEY ?? "";
  if (!secretKey.startsWith("sk_test_")) {
    throw new Error("Refusing to clean up users outside a Clerk development instance.");
  }
  const headers = { Authorization: `Bearer ${secretKey}` };
  const cutoff = Date.now() - STALE_AFTER_MS;

  try {
    const stale: ClerkUser[] = [];
    for (let offset = 0; ; offset += PAGE_SIZE) {
      const params = new URLSearchParams({
        query: "+clerk_test",
        order_by: "+created_at",
        limit: String(PAGE_SIZE),
        offset: String(offset),
      });
      const response = await fetch(`${CLERK_API}/users?${params}`, { headers });
      if (!response.ok) throw new Error(`listing users: HTTP ${response.status}`);
      const users: ClerkUser[] = await response.json();
      stale.push(
        ...users.filter(
          (user) =>
            user.created_at < cutoff &&
            user.email_addresses.some((e) => e.email_address.includes("+clerk_test@")),
        ),
      );
      if (users.length < PAGE_SIZE) break;
    }

    for (const user of stale) {
      const response = await fetch(`${CLERK_API}/users/${user.id}`, { method: "DELETE", headers });
      if (!response.ok) throw new Error(`deleting ${user.id}: HTTP ${response.status}`);
    }
    console.log(`Deleted ${stale.length} stale Clerk test user(s).`);
  } catch (error) {
    console.warn(`Clerk test user cleanup failed: ${error}`);
  }
});

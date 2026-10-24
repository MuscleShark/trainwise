import { clerkSetup } from "@clerk/testing/playwright";
import { test as setup } from "@playwright/test";

// Fetches a Clerk testing token so tests can pass Clerk's bot protection.
setup("clerk setup", async () => {
  await clerkSetup();
});

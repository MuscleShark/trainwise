import { defineConfig, devices } from "@playwright/test";

// E2E runs on its own ports so it never talks to your local dev servers or dev database.
const FRONTEND_PORT = 3001;
const BACKEND_PORT = 8001;
const FRONTEND_URL = `http://localhost:${FRONTEND_PORT}`;
const BACKEND_URL = `http://localhost:${BACKEND_PORT}`;

const E2E_DATABASE_URL =
  process.env.E2E_DATABASE_URL ??
  "postgresql+psycopg://trainwise:trainwise@localhost:5432/trainwise_e2e";

// Clerk *development* instance keys (test emails like name+clerk_test@example.com
// accept the code 424242). CLERK_SECRET_KEY is only used to fetch a testing token.
const CLERK_PUBLISHABLE_KEY =
  process.env.CLERK_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY ?? "";
const CLERK_SECRET_KEY = process.env.CLERK_SECRET_KEY ?? "";

if (!CLERK_PUBLISHABLE_KEY.startsWith("pk_test_") || !CLERK_SECRET_KEY.startsWith("sk_test_")) {
  throw new Error(
    "E2E needs Clerk development keys: set CLERK_PUBLISHABLE_KEY (pk_test_…) and CLERK_SECRET_KEY (sk_test_…).",
  );
}

// The publishable key encodes the instance's Frontend API host, which is the token issuer.
const CLERK_ISSUER = `https://${Buffer.from(CLERK_PUBLISHABLE_KEY.split("_")[2], "base64")
  .toString()
  .replace(/\$$/, "")}`;

process.env.CLERK_PUBLISHABLE_KEY = CLERK_PUBLISHABLE_KEY;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: FRONTEND_URL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "clerk setup", testMatch: /global\.setup\.ts/ },
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
      dependencies: ["clerk setup"],
    },
  ],
  webServer: [
    {
      command: `.venv/bin/python create_tables.py && .venv/bin/uvicorn main:app --port ${BACKEND_PORT}`,
      cwd: "../backend",
      url: `${BACKEND_URL}/docs`,
      env: {
        DATABASE_URL: E2E_DATABASE_URL,
        CLERK_ISSUER,
        FRONTEND_URL,
      },
      reuseExistingServer: false,
      timeout: 60_000,
    },
    {
      command: `npm run build && npm run start -- --port ${FRONTEND_PORT}`,
      url: FRONTEND_URL,
      env: {
        NEXT_PUBLIC_API_URL: BACKEND_URL,
        NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY: CLERK_PUBLISHABLE_KEY,
        CLERK_SECRET_KEY,
      },
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
});

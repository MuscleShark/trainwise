import { defineConfig, devices } from "@playwright/test";

// E2E runs on its own ports so it never talks to your local dev servers or dev database.
const FRONTEND_PORT = 3001;
const BACKEND_PORT = 8001;
const FRONTEND_URL = `http://localhost:${FRONTEND_PORT}`;
const BACKEND_URL = `http://localhost:${BACKEND_PORT}`;

const E2E_DATABASE_URL =
  process.env.E2E_DATABASE_URL ??
  "postgresql+psycopg://trainwise:trainwise@localhost:5432/trainwise_e2e";

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
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    {
      command: `.venv/bin/python create_tables.py && .venv/bin/uvicorn main:app --port ${BACKEND_PORT}`,
      cwd: "../backend",
      url: `${BACKEND_URL}/docs`,
      env: {
        DATABASE_URL: E2E_DATABASE_URL,
        SECRET_KEY: "e2e-only-secret-key",
        FRONTEND_URL,
      },
      reuseExistingServer: false,
      timeout: 60_000,
    },
    {
      command: `npm run build && npm run start -- --port ${FRONTEND_PORT}`,
      url: FRONTEND_URL,
      env: { NEXT_PUBLIC_API_URL: BACKEND_URL },
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { LEGAL_JSON, legalJson } from "./legal-export.ts";

test("the app's copy of the privacy policy and support matches the site", () => {
  assert.equal(readFileSync(LEGAL_JSON, "utf8"), legalJson(), "Run npm run legal:export and commit the result.");
});

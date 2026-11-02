// The privacy policy and support text for the iPhone app, which ships a copy so the
// pages open without a network. `npm run legal:export` writes it; a test checks the
// copy matches legal-content.ts.
import { writeFileSync } from "node:fs";

import { CONTACT_EMAIL, privacy, support, type Lang, type Page } from "../components/legal-content.ts";

export const LEGAL_JSON = new URL("../../../ios/IronSage/Settings/legal.json", import.meta.url);

function forApp(pages: Record<Lang, Page>) {
  // The link to the other language is the website's; the app follows its own language.
  return Object.fromEntries(
    Object.entries(pages).map(([lang, { title, updated, intro, sections }]) => [lang, { title, updated, intro, sections }]),
  );
}

export function legalJson(): string {
  return JSON.stringify({ contactEmail: CONTACT_EMAIL, privacy: forApp(privacy), support: forApp(support) }, null, 2) + "\n";
}

if (import.meta.url === `file://${process.argv[1]}`) {
  writeFileSync(LEGAL_JSON, legalJson());
  console.log(`Wrote ${LEGAL_JSON.pathname}`);
}

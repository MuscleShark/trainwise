import type { Metadata } from "next";

import LegalPage from "../components/LegalPage";
import { privacy } from "../components/legal-content";

export const metadata: Metadata = { title: "Privacy policy | IronSage" };

export default function Page() {
  return <LegalPage page={privacy.en} lang="en" />;
}

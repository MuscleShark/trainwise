import type { Metadata } from "next";

import LegalPage from "../components/LegalPage";
import { support } from "../components/legal-content";

export const metadata: Metadata = { title: "Support | IronSage" };

export default function Page() {
  return <LegalPage page={support.en} lang="en" />;
}

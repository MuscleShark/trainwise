import type { Metadata } from "next";

import LegalPage from "../../components/LegalPage";
import { privacy } from "../../components/legal-content";

export const metadata: Metadata = { title: "隐私政策 | IronSage" };

export default function Page() {
  return <LegalPage page={privacy.zh} lang="zh" />;
}

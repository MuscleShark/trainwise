import type { Metadata } from "next";

import LegalPage from "../../components/LegalPage";
import { support } from "../../components/legal-content";

export const metadata: Metadata = { title: "客服支持 | IronSage" };

export default function Page() {
  return <LegalPage page={support.zh} lang="zh" />;
}

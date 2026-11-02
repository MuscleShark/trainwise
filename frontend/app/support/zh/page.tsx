import type { Metadata } from "next";

import LegalPage from "../../components/LegalPage";
import { support } from "../../components/legal-content";

export const metadata: Metadata = { title: "客服支持 | IronSage" };

// The iPhone app opens this page in a sheet with `?app=1`: just the text.
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ app?: string }>;
}) {
  const { app } = await searchParams;
  return <LegalPage page={support.zh} lang="zh" inApp={app === "1"} />;
}

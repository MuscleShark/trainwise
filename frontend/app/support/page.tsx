import type { Metadata } from "next";

import LegalPage from "../components/LegalPage";
import { support } from "../components/legal-content";

export const metadata: Metadata = { title: "Support | IronSage" };

// The iPhone app opens this page in a sheet with `?app=1`: just the text.
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ app?: string }>;
}) {
  const { app } = await searchParams;
  return <LegalPage page={support.en} lang="en" inApp={app === "1"} />;
}

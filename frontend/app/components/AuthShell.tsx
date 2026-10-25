import Link from "next/link";

import Logo from "./Logo";

export default function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 px-4 py-12">
      <Link href="/" aria-label="IronSage home">
        <Logo height={96} />
      </Link>
      {children}
    </main>
  );
}

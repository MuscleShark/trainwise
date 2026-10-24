import Link from "next/link";

export default function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 px-4 py-12">
      <Link href="/" className="type-stamp text-xl">
        IronSage
      </Link>
      {children}
    </main>
  );
}

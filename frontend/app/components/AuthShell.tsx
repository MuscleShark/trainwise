import Link from "next/link";

export default function AuthShell({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 bg-slate-950 px-6 py-12 text-white">
      <Link href="/" className="text-lg font-semibold tracking-tight">
        Train<span className="text-emerald-400">Wise</span>
      </Link>
      {children}
    </main>
  );
}

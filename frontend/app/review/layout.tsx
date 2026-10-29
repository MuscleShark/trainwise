"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import Logo from "../components/Logo";
import { TrainingProvider, useReview } from "./data";

/** The signed-in pages for looking back at training. They only read; the app writes. */
export default function ReviewLayout({ children }: { children: React.ReactNode }) {
  return (
    <TrainingProvider>
      <div className="flex flex-1 flex-col">
        <ReviewHeader />
        <main className="mx-auto w-full max-w-5xl flex-1 px-4 pt-6 pb-16 sm:px-8">
          <Content>{children}</Content>
        </main>
      </div>
    </TrainingProvider>
  );
}

function ReviewHeader() {
  const { t } = useReview();
  const pathname = usePathname();
  const links = [
    { href: "/review", label: t.overview },
    { href: "/review/history", label: t.history },
    { href: "/review/exercises", label: t.exercises },
  ];

  return (
    <header className="mx-auto flex w-full max-w-5xl flex-wrap items-center justify-between gap-x-6 gap-y-3 px-4 py-6 sm:px-8">
      <Link href="/" aria-label="IronSage home">
        <Logo height={44} />
      </Link>
      <nav aria-label="Review" className="flex flex-wrap items-center gap-1 text-sm font-medium">
        {links.map((link) => {
          const current = pathname === link.href;
          return (
            <Link
              key={link.href}
              href={link.href}
              aria-current={current ? "page" : undefined}
              className={`rounded-sm px-3 py-2 transition-colors ${
                current ? "bg-ink text-chalk" : "text-steel hover:text-ink"
              }`}
            >
              {link.label}
            </Link>
          );
        })}
        <Link href="/account" className="rounded-sm px-3 py-2 text-steel transition-colors hover:text-ink">
          {t.account}
        </Link>
      </nav>
    </header>
  );
}

/** Loading and error states for every review page. */
function Content({ children }: { children: React.ReactNode }) {
  const { training, error, t } = useReview();
  if (error) {
    return (
      <p role="alert" className="rounded-sm border border-accent/30 bg-card px-4 py-3 text-accent">
        {t.loadFailed}
      </p>
    );
  }
  if (!training) return <p className="text-steel">{t.loading}</p>;
  return (
    <>
      {children}
      <p className="mt-16 border-t border-ink/15 pt-6 text-sm text-steel">{t.readOnly}</p>
    </>
  );
}

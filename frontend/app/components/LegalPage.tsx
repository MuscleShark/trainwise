import Link from "next/link";

import type { Lang, Page } from "./legal-content";
import Logo from "./Logo";

export default function LegalPage({ page, lang }: { page: Page; lang: Lang }) {
  return (
    <div lang={lang === "zh" ? "zh-Hans" : "en"} className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-3xl items-center justify-between px-4 py-6 sm:px-8">
        <Link href="/" aria-label="IronSage home">
          <Logo height={52} />
        </Link>
        <Link
          href={page.otherLanguage.href}
          className="rounded-md px-3 py-2 text-sm font-medium text-steel transition-colors hover:text-ink"
        >
          {page.otherLanguage.label}
        </Link>
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-6 sm:px-8">
        <h1 className="type-stamp text-4xl">{page.title}</h1>
        {page.updated ? <p className="mt-3 text-sm text-steel">{page.updated}</p> : null}
        <p className="mt-6 text-lg leading-relaxed">{page.intro}</p>

        {page.sections.map((section) => (
          <section key={section.heading} className="mt-10">
            <h2 className="text-xl font-semibold">{section.heading}</h2>
            {section.paragraphs?.map((paragraph) => (
              <p key={paragraph} className="mt-3 leading-relaxed text-ink/90">
                {paragraph}
              </p>
            ))}
            {section.items ? (
              <ul className="mt-3 list-disc space-y-2 pl-5 leading-relaxed text-ink/90 marker:text-steel">
                {section.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            ) : null}
          </section>
        ))}
      </main>
    </div>
  );
}

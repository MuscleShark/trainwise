import Link from "next/link";

import { CONTACT_EMAIL, type Lang, type Page } from "./legal-content";
import Logo from "./Logo";

/** The support address in a sentence, as a link that opens a new email. */
function withEmailLink(text: string) {
  const [before, ...rest] = text.split(CONTACT_EMAIL);
  if (rest.length === 0) return text;
  return (
    <>
      {before}
      <a
        href={`mailto:${CONTACT_EMAIL}`}
        className="font-medium text-accent underline-offset-2 hover:underline"
      >
        {CONTACT_EMAIL}
      </a>
      {rest.join(CONTACT_EMAIL)}
    </>
  );
}

/**
 * The privacy policy or support page. `inApp` is the iPhone app's sheet: no site
 * header and no title, which the sheet shows itself.
 */
export default function LegalPage({
  page,
  lang,
  inApp = false,
}: {
  page: Page;
  lang: Lang;
  inApp?: boolean;
}) {
  return (
    <div
      lang={lang === "zh" ? "zh-Hans" : "en"}
      className="flex flex-1 flex-col"
    >
      {inApp ? null : (
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
      )}

      <main
        className={`mx-auto w-full max-w-3xl flex-1 px-4 pb-16 sm:px-8 ${inApp ? "pt-4" : "pt-6"}`}
      >
        {inApp ? null : <h1 className="type-stamp text-4xl">{page.title}</h1>}
        {page.updated ? (
          <p className={`${inApp ? "" : "mt-3 "}text-sm text-steel`}>
            {page.updated}
          </p>
        ) : null}
        <p
          className={`${inApp && !page.updated ? "" : "mt-6 "}text-lg leading-relaxed`}
        >
          {withEmailLink(page.intro)}
        </p>

        {page.sections.map((section) => (
          <section key={section.heading} className="mt-10">
            <h2 className="text-xl font-semibold">{section.heading}</h2>
            {section.paragraphs?.map((paragraph) => (
              <p key={paragraph} className="mt-3 leading-relaxed text-ink/90">
                {withEmailLink(paragraph)}
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

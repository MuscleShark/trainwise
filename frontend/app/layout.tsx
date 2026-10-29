import type { Metadata, Viewport } from "next";
import { Archivo, Barlow_Condensed } from "next/font/google";
import { ClerkProvider } from "@clerk/nextjs";
import "./globals.css";

const archivo = Archivo({
  subsets: ["latin"],
  axes: ["wdth"],
  variable: "--font-archivo",
});

// The logo's typeface, for headings.
const barlowCondensed = Barlow_Condensed({
  subsets: ["latin"],
  weight: "800",
  variable: "--font-barlow-condensed",
});

export const metadata: Metadata = {
  title: "IronSage",
  description:
    "A strength-training log for iPhone with a coach that suggests your next weights and explains why.",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f4efe6" },
    { media: "(prefers-color-scheme: dark)", color: "#161514" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${archivo.variable} ${barlowCondensed.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <ClerkProvider
          signInUrl="/login"
          signUpUrl="/register"
          signInFallbackRedirectUrl="/review"
          signUpFallbackRedirectUrl="/review"
          // The brand tokens from globals.css, so the card follows the color scheme.
          appearance={{
            variables: {
              colorPrimary: "var(--ink)",
              colorPrimaryForeground: "var(--chalk)",
              colorForeground: "var(--ink)",
              colorMutedForeground: "var(--steel)",
              colorNeutral: "var(--ink)",
              colorBackground: "var(--card)",
              colorInput: "var(--card)",
              colorInputForeground: "var(--ink)",
              colorDanger: "var(--accent)",
              colorRing: "var(--accent)",
              fontFamily: "var(--font-archivo), ui-sans-serif, system-ui, sans-serif",
              borderRadius: "0.5rem",
            },
          }}
        >
          {children}
        </ClerkProvider>
      </body>
    </html>
  );
}

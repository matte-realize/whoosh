import type { Metadata } from "next";
import { Barlow, Barlow_Condensed } from "next/font/google";
import { Logo } from "@/components/Logo";
import { SiteNav } from "@/components/SiteNav";
import "./globals.css";

/*
 * Barlow (body) and Barlow Condensed (headings and numbers): a narrow, DIN-style sports family.
 * next/font downloads the files at build time and serves them from this site, so visitors'
 * browsers never contact Google. Both are under the SIL Open Font License.
 */
const body = Barlow({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-body",
  display: "swap",
});

const display = Barlow_Condensed({
  subsets: ["latin"],
  weight: ["500", "600", "700", "800"],
  variable: "--font-display",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Whoosh: a heads-up for what's behind you",
  description:
    "Whoosh turns the phone on your bike into a rear-view companion: a tap or a tone when a car is coming up behind you. In development for iPhone.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${body.variable} ${display.variable}`}>
      <body>
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <SiteNav />
        <div id="main">{children}</div>
        <footer className="site-footer">
          <div className="site-footer__brand">
            <Logo size={24} />
            <span>Made in Boston. In development for iPhone.</span>
          </div>
          <span>
            Whoosh gives a heads-up, not a guarantee, and is not a safety device. Map data ©
            OpenStreetMap contributors.
          </span>
        </footer>
      </body>
    </html>
  );
}

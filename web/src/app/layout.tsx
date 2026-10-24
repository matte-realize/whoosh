import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Whoosh",
  description: "Awareness of traffic behind you on a bike, using the phone you already own.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <nav className="site-nav" aria-label="Site">
          <Link href="/" className="site-nav__brand">
            Whoosh
          </Link>
          <Link href="/">Project</Link>
          <Link href="/dashboard">Live dashboard</Link>
        </nav>
        {children}
        <footer className="site-footer">
          Hackathon prototype. Experimental vehicle detection; not a safety device.
        </footer>
      </body>
    </html>
  );
}

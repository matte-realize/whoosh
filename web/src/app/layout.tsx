import type { Metadata } from "next";
import { Logo } from "@/components/Logo";
import { SiteNav } from "@/components/SiteNav";
import "./globals.css";

export const metadata: Metadata = {
  title: "Whoosh: a heads-up for what's behind you",
  description:
    "Whoosh turns the phone on your bike into a rear-view companion: a tap or a tone when a car is coming up behind you. In development for iPhone.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
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

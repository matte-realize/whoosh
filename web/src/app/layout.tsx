import type { Metadata } from "next";
import { SiteNav } from "@/components/SiteNav";
import "./globals.css";

export const metadata: Metadata = {
  title: "Whoosh",
  description: "Awareness of traffic behind you on a bike, using the phone you already own.",
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
          <span>Whoosh, a Hackachusetts prototype.</span>
          <span>Experimental vehicle detection; not a safety device. Map data © OpenStreetMap contributors.</span>
        </footer>
      </body>
    </html>
  );
}

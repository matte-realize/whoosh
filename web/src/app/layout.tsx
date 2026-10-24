import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Whoosh rides",
  description: "Rides that Whoosh riders chose to share.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

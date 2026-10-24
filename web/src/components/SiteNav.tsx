"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "./Logo";

const LINKS = [
  { href: "/simulation", label: "See it in action" },
  { href: "/dashboard", label: "Ride map" },
];

/** Top navigation. Marks the current page for screen readers and visually. */
export function SiteNav() {
  const pathname = usePathname();
  return (
    <header className="site-header">
      <nav className="site-nav" aria-label="Site">
        <Link href="/" className="site-nav__brand" aria-label="Whoosh home">
          <Logo size={30} />
        </Link>
        <div className="site-nav__links">
          {LINKS.map((link) => {
            const current = pathname === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className="site-nav__link"
                aria-current={current ? "page" : undefined}
              >
                {link.label}
              </Link>
            );
          })}
        </div>
      </nav>
    </header>
  );
}

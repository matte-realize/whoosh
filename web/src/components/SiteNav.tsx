"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/", label: "Project" },
  { href: "/simulation", label: "Simulation" },
  { href: "/dashboard", label: "Live dashboard" },
];

/** Top navigation. Marks the current page for screen readers and visually. */
export function SiteNav() {
  const pathname = usePathname();
  return (
    <header className="site-header">
      <nav className="site-nav" aria-label="Site">
        <Link href="/" className="site-nav__brand">
          <span className="site-nav__logo" aria-hidden="true">
            W
          </span>
          Whoosh
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

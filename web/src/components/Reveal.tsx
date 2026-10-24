"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/**
 * Fades its content in when it scrolls into view. Content is visible before JavaScript runs and
 * for anyone who asks for reduced motion (see `.reveal` in globals.css), so nothing can stay hidden.
 */
export function Reveal({ children, className }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<"idle" | "armed" | "shown">("idle");

  useEffect(() => {
    const element = ref.current;
    if (element === null) return;
    if (!("IntersectionObserver" in window)) {
      setState("shown");
      return;
    }
    setState("armed");
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setState("shown");
          observer.disconnect();
        }
      },
      { threshold: 0.12 },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} className={`reveal reveal--${state}${className ? ` ${className}` : ""}`}>
      {children}
    </div>
  );
}

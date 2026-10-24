import type { Metadata } from "next";
import CommunityMapSection from "@/components/CommunityMapSection";
import Dashboard from "@/components/Dashboard";
import StatsPanel from "@/components/StatsPanel";

export const metadata: Metadata = {
  title: "Whoosh live dashboard",
  description: "Rides and reports that Whoosh riders chose to share.",
};

export default function DashboardPage() {
  return (
    <main className="page">
      <header>
        <h1>Live dashboard</h1>
        <p className="subtitle">Rides and reports that riders chose to share.</p>
      </header>
      <StatsPanel />
      <CommunityMapSection />
      <section className="rides-section" aria-labelledby="rides-heading">
        <h2 id="rides-heading">Shared rides</h2>
        <Dashboard />
      </section>
    </main>
  );
}

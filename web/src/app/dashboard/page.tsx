import type { Metadata } from "next";
import CommunityInsights from "@/components/CommunityInsights";
import CommunityMapSection from "@/components/CommunityMapSection";
import Dashboard from "@/components/Dashboard";
import StatsPanel from "@/components/StatsPanel";

export const metadata: Metadata = {
  title: "Whoosh ride map",
  description: "Rides and close calls that Whoosh riders chose to share.",
};

export default function DashboardPage() {
  return (
    <main className="page dashboard">
      <header className="page-header">
        <p className="eyebrow">Ride map</p>
        <h1>Shared by Whoosh riders</h1>
        <p className="subtitle">
          Rides and close calls that riders chose to share along Massachusetts Avenue in Boston,
          next to the bike crashes the City of Boston has published for the same street. Only what
          riders share is shown.
        </p>
      </header>
      <StatsPanel />
      <CommunityMapSection />
      <CommunityInsights />
      <section className="rides-section card" aria-labelledby="rides-heading">
        <div className="section-head">
          <h2 id="rides-heading">Shared rides</h2>
        </div>
        <Dashboard />
      </section>
    </main>
  );
}

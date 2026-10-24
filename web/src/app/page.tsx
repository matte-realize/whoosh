import CommunityMapSection from "@/components/CommunityMapSection";
import Dashboard from "@/components/Dashboard";
import StatsPanel from "@/components/StatsPanel";

export default function Page() {
  return (
    <main className="page">
      <header>
        <h1>Whoosh</h1>
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

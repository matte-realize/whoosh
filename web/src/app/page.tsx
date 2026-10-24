import Dashboard from "@/components/Dashboard";

export default function Page() {
  return (
    <main className="page">
      <header>
        <h1>Whoosh rides</h1>
        <p className="subtitle">Rides that riders chose to share.</p>
      </header>
      <Dashboard />
    </main>
  );
}

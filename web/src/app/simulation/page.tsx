import type { Metadata } from "next";
import Link from "next/link";
import SimulationClient from "@/components/SimulationClient";

export const metadata: Metadata = {
  title: "Whoosh ride simulation",
  description: "A 3D simulation of how the Whoosh app is designed to warn a cyclist about traffic behind them.",
};

export default function SimulationPage() {
  return (
    <main className="page simulation">
      <header className="page-header">
        <p className="eyebrow">Interactive demo</p>
        <h1>Ride simulation</h1>
        <p className="subtitle">
          A rider in a Massachusetts Avenue-style bike lane, cars coming up from behind, and the cue the
          app is designed to give. Rotate the 3D view, switch to the phone&apos;s rear camera, and try
          different traffic.
        </p>
      </header>

      <SimulationClient />

      <section className="sim-explainer" aria-labelledby="sim-how-heading">
        <h2 id="sim-how-heading">What you are watching</h2>
        <div className="sim-explainer__grid">
          <div className="card">
            <h3>Tracking</h3>
            <p>
              A vehicle behind the rider and getting closer, within 60 m, turns amber. The label shows how
              far back it is and how many seconds until it reaches the rider.
            </p>
          </div>
          <div className="card">
            <h3>Caution cue</h3>
            <p>
              When it is about 3.5 seconds or 10 m away, it turns red and the app gives one cue: a banner, a
              wrist tap, and a sound if you turn sound on. One cue per vehicle, never a stream.
            </p>
          </div>
          <div className="card">
            <h3>Not flagged</h3>
            <p>
              Oncoming traffic on the other side of the road is ignored, because it is not coming up behind
              the rider. Left and right are always the rider&apos;s own left and right.
            </p>
          </div>
        </div>
      </section>

      <section className="honesty" aria-labelledby="sim-honesty-heading">
        <h2 id="sim-honesty-heading">This is a simulation</h2>
        <p>
          It shows how the app is designed to behave, not how it performs. The simulated detector knows
          exactly where every vehicle is. The real one only has a camera image, is experimental, has not
          been measured yet, and will miss vehicles and raise false alarms. Turn on <strong>Show detector
          mistakes</strong> to see what that looks like. The distances, timings and thresholds here are
          illustrative values, not the app&apos;s tuning. Whoosh does not predict or prevent collisions.
        </p>
        <p>
          <Link href="/">Back to the project</Link> · <Link href="/dashboard">Live dashboard</Link>
        </p>
      </section>
    </main>
  );
}

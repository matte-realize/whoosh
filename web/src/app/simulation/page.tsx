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
        <p className="eyebrow">See it in action</p>
        <h1>Take a ride with Whoosh</h1>
        <p className="subtitle">
          A ride up the Mass Ave bike lane in Boston, with the rider&apos;s phone, Watch and emergency
          contact alongside. Pick a feature: ride recording, near-miss logging, or crash response.
        </p>
      </header>

      <SimulationClient />

      <section className="sim-explainer" aria-labelledby="sim-how-heading">
        <h2 id="sim-how-heading">What you are watching</h2>
        <div className="sim-explainer__grid">
          <div className="card">
            <h3>1 · Ride recording</h3>
            <p>
              The rider taps Start Ride. The phone records ride time, distance, speed and the route on
              the map, and the paired Watch shows the same numbers. Everything stays on the phone.
            </p>
          </div>
          <div className="card">
            <h3>2 · Near-miss logging</h3>
            <p>
              The rear camera spots a car closing from behind. The rider gets one caution cue, and the
              app logs a near miss with the side, the detector&apos;s score and where it happened. The
              rider can also tap Mark close call. No video is kept.
            </p>
          </div>
          <div className="card">
            <h3>3 · Crash response</h3>
            <p>
              A simulated crash starts a countdown with a large I&apos;m OK button on the phone and the
              Watch. If nobody taps it, the emergency contact gets a text with a map link. Drills say
              &ldquo;DEMO - NOT REAL&rdquo;.
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
          mistakes</strong> (under Free ride) to see what that looks like. The distances, timings and
          thresholds here are illustrative values, not the app&apos;s tuning. Whoosh does not predict or
          prevent collisions.
        </p>
        <p>
          The crash countdown here is 15 seconds, the shortest the design allows; the app&apos;s default
          is 30. Real crash detection is experimental and will miss crashes and raise false ones, which
          is why the rider always gets a chance to cancel. Whoosh is not an emergency service and
          cannot guarantee that an alert is sent, delivered or read. The phone number and names are
          made up.
        </p>
        <p>
          <Link href="/">Back to Whoosh</Link> · <Link href="/dashboard">Explore the ride map</Link>
        </p>
      </section>
    </main>
  );
}

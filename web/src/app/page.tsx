import Link from "next/link";
import StatsPanel from "@/components/StatsPanel";
import { FEATURES, STATUS_CHECKED_ON, STATUS_LABEL, STATUS_SYMBOL } from "@/lib/projectStatus";

/** The project page: what Whoosh is, how it works, how it protects riders, and what is built. */
export default function ProjectPage() {
  return (
    <main className="page project">
      <header className="hero">
        <p className="hero__eyebrow">Hackachusetts project</p>
        <h1>Whoosh</h1>
        <p className="hero__lead">
          Awareness of what is coming up behind you on a bike, using the phone you already own.
          No extra hardware, no account, and your rides stay on your phone unless you choose to
          share them.
        </p>
        <div className="hero__actions">
          <Link className="button button--primary" href="/dashboard">
            See the live dashboard
          </Link>
          <a className="button" href="#how-it-works">
            How it works
          </a>
        </div>
      </header>

      <section aria-labelledby="problem-heading">
        <h2 id="problem-heading">The problem</h2>
        <p>
          On a bike, traffic coming up behind you is hard to see without turning your head. Mirrors
          and rear radar units help, but they cost money and need fitting. Whoosh tries to give
          riders some of that awareness from a phone mounted on the bike.
        </p>
      </section>

      <section aria-labelledby="features-heading">
        <h2 id="features-heading">What it does</h2>
        <p className="note">
          Status as of {STATUS_CHECKED_ON}. A feature is marked tested only when an automated test
          or a recorded run backs it.
        </p>
        <ul className="feature-grid">
          {FEATURES.map((feature) => (
            <li key={feature.name} className="feature-card">
              <h3>{feature.name}</h3>
              <p>{feature.summary}</p>
              <p className={`status status--${feature.status}`}>
                <span aria-hidden="true">{STATUS_SYMBOL[feature.status]} </span>
                {STATUS_LABEL[feature.status]}
              </p>
              <p className="status-note">{feature.statusNote}</p>
            </li>
          ))}
        </ul>
      </section>

      <section id="how-it-works" aria-labelledby="how-heading">
        <h2 id="how-heading">How it works</h2>
        <ol className="flow">
          <li>
            <h3>On the phone</h3>
            <p>
              The app records the ride with GPS and keeps it on the phone. Detection, if turned on,
              runs on the phone too, so a caution cue never waits on a network.
            </p>
          </li>
          <li>
            <h3>If the rider opts in</h3>
            <p>
              The finished ride is backed up under an anonymous account. Before upload, the first and
              last 160 m (about 0.1 mi) of the route are cut off so home and work stay private.
            </p>
          </li>
          <li>
            <h3>On this website</h3>
            <p>
              Only rides the rider chose to share, and incident areas that pass the privacy rules
              below, are shown. The website never sees who a ride belongs to.
            </p>
          </li>
        </ol>
      </section>

      <section aria-labelledby="privacy-heading">
        <h2 id="privacy-heading">Privacy, in specifics</h2>
        <ul className="checklist">
          <li>Every core feature works offline, with no account.</li>
          <li>Cloud backup is off by default. Sharing a ride publicly is a separate choice, per ride.</li>
          <li>Each shared route is trimmed by 160 m at both ends before it leaves the phone.</li>
          <li>
            Incidents appear only as areas of about 100 m, with at least 3 reports from at least 2
            riders, and only after a 24-hour delay. Single reports are never shown.
          </li>
          <li>Rider counts are hidden until at least 3 riders have shared.</li>
          <li>Anonymous sign-in: no email, name, or phone number is collected.</li>
          <li>
            The database lets each rider read and change only their own rows. Automated tests check
            this, and check that the public website can read only the summary views.
          </li>
          <li>No analytics or tracking code. Camera video is never uploaded.</li>
        </ul>
      </section>

      <section className="honesty" aria-labelledby="honesty-heading">
        <h2 id="honesty-heading">What Whoosh is not</h2>
        <p>
          Whoosh is a hackathon prototype. Vehicle detection is experimental and has not been
          measured yet. It does not predict or prevent collisions, it can miss vehicles and raise
          false alarms, and it is not a substitute for looking and riding carefully. The incident map
          shows unverified reports: an area with no reports is not a safe area.
        </p>
      </section>

      <section aria-label="Live numbers">
        <StatsPanel />
        <p className="note">
          <Link href="/dashboard">Open the dashboard</Link> for the community map and each shared ride.
        </p>
      </section>

      <section aria-labelledby="stack-heading">
        <h2 id="stack-heading">How it is built</h2>
        <dl className="stack">
          <div>
            <dt>iPhone app</dt>
            <dd>SwiftUI, Core Location, MapKit, SwiftData. Vision and Core ML for detection.</dd>
          </div>
          <div>
            <dt>Backend</dt>
            <dd>
              Supabase (Postgres) with row-level security, anonymous sign-in, privacy-filtered public
              views, and upload limits, covered by pgTAP tests.
            </dd>
          </div>
          <div>
            <dt>Website</dt>
            <dd>Next.js, Leaflet, and OpenStreetMap. No map API keys, no tracking.</dd>
          </div>
        </dl>
      </section>

      <section aria-labelledby="team-heading">
        <h2 id="team-heading">Team</h2>
        <ul className="team">
          <li>
            <strong>iOS app:</strong> ride recording, maps, on-phone storage, and alerts.
          </li>
          <li>
            <strong>Vision:</strong> on-device vehicle detection and its measured performance.
          </li>
          <li>
            <strong>Backend and website:</strong> database, privacy rules, this site, and the data
            contracts between the three.
          </li>
        </ul>
      </section>
    </main>
  );
}

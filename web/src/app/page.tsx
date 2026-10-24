import Link from "next/link";
import { FeatureExplorer } from "@/components/FeatureExplorer";
import { HeroVisual } from "@/components/HeroVisual";
import { HowItWorks } from "@/components/HowItWorks";
import { Icon } from "@/components/Icon";
import { Reveal } from "@/components/Reveal";
import StatsPanel from "@/components/StatsPanel";
import { STATUS_CHECKED_ON } from "@/lib/projectStatus";

const PRIVACY_POINTS = [
  "Every core feature is designed to work offline, with no account.",
  "Cloud backup is off by default. Sharing a ride publicly is a separate choice, per ride.",
  "Each shared route is trimmed by 160 m at both ends before it leaves the phone.",
  "Incidents appear only as areas of about 100 m, with at least 3 reports from at least 2 riders, after a 24-hour delay.",
  "Rider counts stay hidden until at least 3 riders have shared.",
  "Anonymous sign-in: no email, name, or phone number is collected.",
  "Each rider can read and change only their own data. Automated tests check this.",
  "No analytics or tracking code. Camera video is never uploaded.",
];

const FAQ = [
  {
    q: "Does camera video leave my phone?",
    a: "No. Detection is designed to run on the phone, and video and frames are never uploaded. Only a detection's time, its place on your route, the vehicle type, the score, and the side can be saved, and only if you opt in to cloud backup.",
  },
  {
    q: "Do I need an account?",
    a: "No. Recording and history are designed to work with no account and no network. Cloud backup, if you turn it on, uses an anonymous account with no email or password.",
  },
  {
    q: "What does this website show about me?",
    a: "Only rides you chose to share, with the first and last 160 m removed, and never with who they belong to. Your incident reports count toward an area only if you opt in, and an area appears only once enough riders have reported there.",
  },
  {
    q: "Can Whoosh prevent a crash?",
    a: "No. Detection is experimental and has not been measured yet. It can miss vehicles and raise false alarms. Keep looking and riding carefully.",
  },
  {
    q: "Is an area with no reports safe?",
    a: "No. The map counts reports from a small number of riders. It cannot say how many people rode through a place, so it is not a safety rating.",
  },
];

/** The project page: what Whoosh is, how it works, how it protects riders, and what is built. */
export default function ProjectPage() {
  return (
    <main className="project">
      <section className="hero">
        <div className="hero__inner">
          <div className="hero__text">
            <p className="eyebrow">Hackachusetts project</p>
            <h1>
              More awareness of the road <span className="gradient-text">behind you.</span>
            </h1>
            <p className="hero__lead">
              Whoosh is a cycling app designed to use the phone you already own to watch the road
              behind you. No extra hardware, no account, and your rides stay on your phone unless
              you choose to share them.
            </p>
            <div className="hero__actions">
              <Link className="button button--primary" href="/simulation">
                Try the 3D simulation
                <span aria-hidden="true"> →</span>
              </Link>
              <Link className="button button--ghost" href="/dashboard">
                Live dashboard
              </Link>
            </div>
            <p className="hero__fine">Experimental prototype. Not a safety device.</p>
          </div>
          <HeroVisual />
        </div>
      </section>

      <div className="page">
        <Reveal>
          <StatsPanel />
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="problem-heading" className="split">
            <div>
              <p className="eyebrow">The problem</p>
              <h2 id="problem-heading">The traffic you can&apos;t see</h2>
            </div>
            <div>
              <p className="lead">
                On a bike, traffic coming up behind you is hard to see without turning your head.
                Mirrors and rear radar units help, but they cost money and need fitting.
              </p>
              <p>
                Whoosh tries to give riders some of that awareness from a phone mounted on the bike,
                with a cue they can feel or hear instead of a screen they have to look at.
              </p>
            </div>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="features-heading">
            <p className="eyebrow">What it does</p>
            <h2 id="features-heading">Features and where each one stands</h2>
            <p className="note">
              Status as of {STATUS_CHECKED_ON}. A feature is marked tested only when an automated
              test or a recorded run backs it.
            </p>
            <FeatureExplorer />
          </section>
        </Reveal>

        <Reveal className="section">
          <section id="how-it-works" aria-labelledby="how-heading">
            <p className="eyebrow">How it works</p>
            <h2 id="how-heading">From the bike to this page</h2>
            <p className="note">How Whoosh is designed to work. The feature list above shows what is built.</p>
            <HowItWorks />
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="privacy-heading" className="card card--accent">
            <div className="section-head">
              <div>
                <p className="eyebrow">
                  <Icon name="lock" size={16} /> Privacy
                </p>
                <h2 id="privacy-heading">Privacy, in specifics</h2>
              </div>
            </div>
            <ul className="checklist checklist--columns">
              {PRIVACY_POINTS.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="faq-heading">
            <p className="eyebrow">Questions</p>
            <h2 id="faq-heading">Common questions</h2>
            <div className="faq">
              {FAQ.map((item) => (
                <details key={item.q}>
                  <summary>{item.q}</summary>
                  <p>{item.a}</p>
                </details>
              ))}
            </div>
          </section>
        </Reveal>

        <Reveal className="section">
          <section className="honesty" aria-labelledby="honesty-heading">
            <h2 id="honesty-heading">What Whoosh is not</h2>
            <p>
              Whoosh is a hackathon prototype. Vehicle detection is experimental and has not been
              measured yet. It does not predict or prevent collisions, it can miss vehicles and raise
              false alarms, and it is not a substitute for looking and riding carefully. The incident
              map shows unverified reports: an area with no reports is not a safe area.
            </p>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="stack-heading" className="split">
            <div>
              <p className="eyebrow">Under the hood</p>
              <h2 id="stack-heading">How it is built</h2>
            </div>
            <dl className="stack">
              <div>
                <dt>iPhone app</dt>
                <dd>SwiftUI, Core Location, MapKit, SwiftData. Vision and Core ML for detection.</dd>
              </div>
              <div>
                <dt>Backend</dt>
                <dd>
                  Supabase (Postgres) with row-level security, anonymous sign-in, privacy-filtered
                  public views, and upload limits, covered by pgTAP tests.
                </dd>
              </div>
              <div>
                <dt>Website</dt>
                <dd>Next.js, Leaflet, and OpenStreetMap. No map API keys, no tracking.</dd>
              </div>
            </dl>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="team-heading">
            <p className="eyebrow">Team</p>
            <h2 id="team-heading">Three roles, one contract</h2>
            <ul className="team-grid">
              <li className="card">
                <Icon name="phone" />
                <h3>iOS app</h3>
                <p>Ride recording, maps, on-phone storage, and alerts.</p>
              </li>
              <li className="card">
                <Icon name="alert" />
                <h3>Vision</h3>
                <p>On-device vehicle detection and its measured performance.</p>
              </li>
              <li className="card">
                <Icon name="cloud" />
                <h3>Backend and website</h3>
                <p>Database, privacy rules, this site, and the data contracts between the three.</p>
              </li>
            </ul>
          </section>
        </Reveal>

        <Reveal className="section">
          <section className="cta" aria-labelledby="cta-heading">
            <h2 id="cta-heading">See the community map</h2>
            <p>Shared routes, incident areas, and every shared ride, live.</p>
            <Link className="button button--primary" href="/dashboard">
              Open the live dashboard
              <span aria-hidden="true"> →</span>
            </Link>
          </section>
        </Reveal>
      </div>
    </main>
  );
}

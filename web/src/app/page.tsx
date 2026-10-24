import Link from "next/link";
import { HeroVisual } from "@/components/HeroVisual";
import IntroFilm from "@/components/IntroFilm";
import { Ring } from "@/components/Ring";
import StatsPanel from "@/components/StatsPanel";
import { FEATURES, STATUS_CHECKED_ON, STATUS_LABEL, STATUS_SYMBOL } from "@/lib/projectStatus";

const STEPS: { title: string; body: string }[] = [
  {
    title: "Mount your phone under the saddle, camera facing back.",
    body: "Any iPhone and a standard seat-post mount. There is nothing else to buy.",
  },
  {
    title: "Start a ride and put the phone out of mind.",
    body: "Whoosh records your route and watches the road behind you. It doesn't need a signal.",
  },
  {
    title: "When a car comes up behind you, you'll know.",
    body: "A tap on your watch or a short tone tells you which side it's on. You never need to look at the screen.",
  },
];

/** Facts about how Whoosh is designed. None of these is a performance claim. */
const NUMBERS: { label: string; value: string; unit?: string; detail: string; tone: string }[] = [
  { label: "Extra gear", value: "0", detail: "Your phone and a mount.", tone: "green" },
  { label: "Accounts", value: "0", detail: "No email, no password.", tone: "blue" },
  { label: "Privacy trim", value: "160", unit: "m", detail: "Removed from each end of a shared route.", tone: "amber" },
  { label: "Riders per close call", value: "2+", detail: "Before a spot appears on the map.", tone: "red" },
];

const PRIVACY: string[] = [
  "Rides are stored on your phone. Nothing is uploaded unless you turn on backup or sharing.",
  "Camera video is processed on the phone and never sent anywhere.",
  "There is no account. Backup, if you use it, doesn't ask for an email, name or phone number.",
  "When you share a ride, the first and last 160 m are cut off so your home and work stay private.",
  "A close call only shows on the public map after at least two riders report the same spot, and never on the same day.",
  "No ads, no analytics, no tracking.",
];

const FAQ = [
  {
    q: "What do I need?",
    a: "An iPhone and a seat-post phone mount. A watch is optional; it's for the wrist tap.",
  },
  {
    q: "Is my camera video uploaded?",
    a: "No. Whoosh looks at the video on the phone and discards it as it goes.",
  },
  {
    q: "Will it stop a crash?",
    a: "No. It gives you a heads-up. It can miss a car and it can alert when nothing is there, so keep riding the way you always do.",
  },
  {
    q: "When can I get it?",
    a: "Whoosh is in development for iPhone. The ride map and the simulation on this site work today.",
  },
];

export default function HomePage() {
  return (
    <main className="project">
      <section className="hero">
        <div className="hero__inner">
          <div className="hero__text">
            <p className="hero__kicker">In development for iPhone</p>
            <h1>A heads-up for what&apos;s behind you.</h1>
            <p className="hero__lead">
              Whoosh turns the phone on your bike into a rear-view companion. When a car is coming up
              behind you, you&apos;ll feel a tap or hear a tone, so you can keep your eyes on the road
              ahead.
            </p>
            <div className="hero__actions">
              <a className="button button--primary" href="#film">
                Watch the film
              </a>
              <Link className="button button--ghost" href="/simulation">
                Try the simulation
              </Link>
            </div>
            <p className="hero__fine">A heads-up, not a guarantee. Always look and ride carefully.</p>
          </div>
          <HeroVisual />
        </div>
      </section>

      <div className="page">
        <section id="film" className="film-section" aria-labelledby="film-heading">
          <h2 id="film-heading" className="film-section__title">
            A 16-second ride
          </h2>
          <IntroFilm />
        </section>

        <section className="section split" aria-labelledby="how-heading">
          <h2 id="how-heading">How it works</h2>
          <ol className="plain-steps">
            {STEPS.map((stepItem, index) => (
              <li key={stepItem.title}>
                <span className="plain-steps__n" aria-hidden="true">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <div>
                  <h3>{stepItem.title}</h3>
                  <p>{stepItem.body}</p>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section className="section bignums" aria-labelledby="bignums-heading">
          <h2 id="bignums-heading" className="visually-hidden">
            Whoosh by the numbers
          </h2>
          <dl className="bignums__grid">
            {NUMBERS.map((item) => (
              <div key={item.label} className={`bignum bignum--${item.tone}`}>
                <dt>{item.label}</dt>
                <dd>
                  {item.value}
                  {item.unit ? <span className="bignum__unit">{item.unit}</span> : null}
                </dd>
                <p>{item.detail}</p>
              </div>
            ))}
          </dl>
        </section>

        <section className="section concept" aria-labelledby="concept-heading">
          <div className="concept__text">
            <h2 id="concept-heading">After the ride</h2>
            <p className="lead">
              When you stop, Whoosh shows how far you went, how long you were actually moving, and each
              heads-up it gave you.
            </p>
            <p>
              Moving time leaves out red lights and stops. Each heads-up is listed with the time and the
              side the car came from, so you can see where your route gets busy.
            </p>
          </div>
          <div className="concept__phone" aria-label="Concept design of the ride summary screen, with example numbers">
            <p className="concept__tag">Concept design, example ride</p>
            <p className="concept__title">Evening ride</p>
            <p className="concept__sub">Mass Ave, Cambridge to Back Bay</p>
            <div className="concept__ring">
              <Ring value={0.92} display="92%" label="Moving" caption="24 of 26 minutes" tone="green" size={176} />
            </div>
            <dl className="concept__stats">
              <div>
                <dt>Distance</dt>
                <dd>4.2 mi</dd>
              </div>
              <div>
                <dt>Avg speed</dt>
                <dd>10.5 mph</dd>
              </div>
              <div>
                <dt>Heads-ups</dt>
                <dd>3</dd>
              </div>
            </dl>
            <ul className="concept__cues">
              <li>
                <span className="concept__time">6:12 pm</span> Car on your left
              </li>
              <li>
                <span className="concept__time">6:19 pm</span> Bus on your left
              </li>
              <li>
                <span className="concept__time">6:27 pm</span> Car directly behind
              </li>
            </ul>
          </div>
        </section>

        <section className="section" aria-labelledby="community-heading">
          <div className="split">
            <h2 id="community-heading">The ride map</h2>
            <div>
              <p className="lead">
                Riders can choose to share a ride or a close call. Shared rides and close calls are
                combined on one public map of Boston, so it&apos;s easier to see which streets need work.
              </p>
              <p>
                <Link href="/dashboard">Open the ride map</Link>
              </p>
            </div>
          </div>
          <StatsPanel />
        </section>

        <section className="section split" aria-labelledby="privacy-heading">
          <h2 id="privacy-heading">Privacy</h2>
          <ul className="plain-list">
            {PRIVACY.map((point) => (
              <li key={point}>{point}</li>
            ))}
          </ul>
        </section>

        <section className="section" aria-labelledby="status-heading">
          <div className="split">
            <h2 id="status-heading">What works today</h2>
            <p className="lead">
              Whoosh is still being built. Here is where each part stands, as of {STATUS_CHECKED_ON}.
            </p>
          </div>
          <div className="table-wrap">
            <table className="status-table">
              <thead>
                <tr>
                  <th scope="col">Feature</th>
                  <th scope="col">Status</th>
                  <th scope="col">Notes</th>
                </tr>
              </thead>
              <tbody>
                {FEATURES.map((feature) => (
                  <tr key={feature.name}>
                    <th scope="row">
                      {feature.name}
                      <span className="status-table__summary">{feature.summary}</span>
                    </th>
                    <td>
                      <span className={`status status--${feature.status}`}>
                        <span aria-hidden="true">{STATUS_SYMBOL[feature.status]} </span>
                        {STATUS_LABEL[feature.status]}
                      </span>
                    </td>
                    <td className="status-table__note">{feature.statusNote}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        <section className="section split" aria-labelledby="faq-heading">
          <h2 id="faq-heading">Questions</h2>
          <dl className="qa">
            {FAQ.map((item) => (
              <div key={item.q}>
                <dt>{item.q}</dt>
                <dd>{item.a}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className="section honesty" aria-labelledby="honesty-heading">
          <h2 id="honesty-heading">What Whoosh can&apos;t do</h2>
          <p>
            The part that spots cars is experimental and hasn&apos;t been measured yet. It can miss a car,
            and it can alert when nothing is there. It doesn&apos;t predict or prevent crashes. Treat it as
            an extra pair of eyes, never a replacement for your own.
          </p>
        </section>
      </div>
    </main>
  );
}

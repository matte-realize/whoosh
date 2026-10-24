import Link from "next/link";
import { FeatureExplorer } from "@/components/FeatureExplorer";
import { HeroVisual } from "@/components/HeroVisual";
import { Icon, type IconName } from "@/components/Icon";
import { LogoMark } from "@/components/Logo";
import { Reveal } from "@/components/Reveal";
import StatsPanel from "@/components/StatsPanel";
import { STATUS_CHECKED_ON } from "@/lib/projectStatus";

const STEPS: { icon: IconName; title: string; body: string }[] = [
  {
    icon: "phone",
    title: "Clip your phone to your bike",
    body: "Mount it facing backward, under the seat. The phone you already have is all you need.",
  },
  {
    icon: "bike",
    title: "Ride like you always do",
    body: "Whoosh keeps an eye on the road behind you and records your ride, even with no signal.",
  },
  {
    icon: "alert",
    title: "Get a heads-up",
    body: "When a car is coming up behind you, feel a tap on your wrist or hear a short tone.",
  },
];

const BENEFITS: { icon: IconName; title: string; body: string }[] = [
  { icon: "bike", title: "No extra gear", body: "No radar to buy and no mirror to fit. Just your phone." },
  { icon: "alert", title: "Eyes on the road", body: "A tap or a tone instead of a screen you have to look at." },
  { icon: "cloud", title: "Works without signal", body: "Everything happens on your phone, so it keeps working in dead zones." },
  { icon: "lock", title: "Private by default", body: "No account, no email. Your rides stay yours." },
  { icon: "map", title: "Better streets, together", body: "Share close calls to show where riding needs to get safer." },
  { icon: "clock", title: "Every ride, saved", body: "Distance, time and route for every ride, right on your phone." },
];

const PRIVACY: string[] = [
  "Your rides stay on your phone unless you choose to back them up or share them.",
  "Camera video never leaves your phone.",
  "No account, email or phone number needed.",
  "Shared routes hide where you start and stop.",
  "A close call only shows on the map once several riders have reported the same spot.",
  "No ads and no tracking.",
];

const FAQ = [
  {
    q: "Do I need any special equipment?",
    a: "No. Whoosh is designed to use your iPhone and a simple bike mount. A watch is optional, for the wrist tap.",
  },
  {
    q: "Does my camera video get uploaded?",
    a: "Never. Whoosh is designed to look at the video on your phone and throw it away as it goes. Nothing from the camera is sent anywhere.",
  },
  {
    q: "Do I need an account?",
    a: "No. Ride tracking works without one. If you choose to back up your rides, Whoosh does it without asking for your email or name.",
  },
  {
    q: "Will Whoosh stop a crash?",
    a: "No. Whoosh gives you a heads-up; it can't see everything and it can be wrong. Keep looking, keep signaling, and ride the way you always would.",
  },
  {
    q: "When can I get it?",
    a: "Whoosh is in development for iPhone. You can try the ride map and the 3D simulation on this site today.",
  },
];

export default function HomePage() {
  return (
    <main className="project">
      <section className="hero">
        <div className="hero__inner">
          <div className="hero__text">
            <p className="pill-badge">
              <span className="pill-badge__dot" aria-hidden="true" />
              In development for iPhone
            </p>
            <h1>
              A heads-up for what&apos;s <span className="gradient-text">behind you.</span>
            </h1>
            <p className="hero__lead">
              Whoosh turns the phone on your bike into a rear-view companion. When a car is coming up
              behind you, you&apos;ll feel a tap or hear a tone, so you can keep your eyes on the road
              ahead.
            </p>
            <div className="hero__actions">
              <Link className="button button--primary" href="/simulation">
                See it in action
                <span aria-hidden="true"> →</span>
              </Link>
              <Link className="button button--ghost" href="/dashboard">
                Explore the ride map
              </Link>
            </div>
            <p className="hero__fine">
              A heads-up, not a guarantee. Always look and ride carefully.
            </p>
          </div>
          <HeroVisual />
        </div>
      </section>

      <div className="page">
        <Reveal className="section section--first">
          <section id="how-it-works" aria-labelledby="how-heading" className="center">
            <p className="eyebrow">How it works</p>
            <h2 id="how-heading">Three steps. No new gear.</h2>
            <ol className="steps-row">
              {STEPS.map((stepItem, index) => (
                <li key={stepItem.title} className="step-card">
                  <span className="step-card__number" aria-hidden="true">
                    {index + 1}
                  </span>
                  <span className="step-card__icon">
                    <Icon name={stepItem.icon} size={30} />
                  </span>
                  <h3>{stepItem.title}</h3>
                  <p>{stepItem.body}</p>
                </li>
              ))}
            </ol>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="why-heading">
            <p className="eyebrow">Why Whoosh</p>
            <h2 id="why-heading">Made for everyday riders</h2>
            <ul className="benefit-grid">
              {BENEFITS.map((benefit) => (
                <li key={benefit.title} className="benefit">
                  <span className="benefit__icon">
                    <Icon name={benefit.icon} />
                  </span>
                  <div>
                    <h3>{benefit.title}</h3>
                    <p>{benefit.body}</p>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        </Reveal>

        <Reveal className="section">
          <section className="showcase" aria-labelledby="showcase-heading">
            <div>
              <p className="eyebrow">See it in action</p>
              <h2 id="showcase-heading">Watch a ride, in 3D</h2>
              <p className="lead">
                Spin around a rider on a city street, watch cars come up from behind, and see the
                moment Whoosh gives its heads-up. You can even look through the phone&apos;s camera.
              </p>
              <Link className="button button--primary" href="/simulation">
                Start the simulation
                <span aria-hidden="true"> →</span>
              </Link>
            </div>
            <div className="showcase__art" aria-hidden="true">
              <div className="showcase__ring">
                <LogoMark size={120} />
              </div>
              <span className="showcase__chip showcase__chip--amber">Car approaching · 24 m</span>
              <span className="showcase__chip showcase__chip--red">Heads-up · on your left</span>
            </div>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="community-heading">
            <div className="split">
              <div>
                <p className="eyebrow">The ride map</p>
                <h2 id="community-heading">Rides and close calls, shared by riders</h2>
              </div>
              <div>
                <p className="lead">
                  When riders choose to share, their rides and close calls come together on one map,
                  so everyone can see where streets need work.
                </p>
                <p>
                  <Link href="/dashboard">Open the ride map</Link>
                </p>
              </div>
            </div>
            <StatsPanel />
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="privacy-heading" className="card card--accent">
            <p className="eyebrow">
              <Icon name="lock" size={16} /> Privacy
            </p>
            <h2 id="privacy-heading">Your rides are yours</h2>
            <ul className="checklist checklist--columns">
              {PRIVACY.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="today-heading">
            <p className="eyebrow">Where Whoosh is today</p>
            <h2 id="today-heading">What you can try, and what&apos;s coming</h2>
            <p className="note">Updated {STATUS_CHECKED_ON}.</p>
            <FeatureExplorer />
          </section>
        </Reveal>

        <Reveal className="section">
          <section aria-labelledby="faq-heading">
            <p className="eyebrow">Questions</p>
            <h2 id="faq-heading">Good questions</h2>
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
            <h2 id="honesty-heading">A heads-up, not a guarantee</h2>
            <p>
              Whoosh is still being built, and the part that spots cars is experimental. It can miss
              a car, and it can sometimes alert when nothing is there. It doesn&apos;t predict or
              prevent crashes. Use it as an extra pair of eyes, never instead of your own.
            </p>
          </section>
        </Reveal>

        <Reveal className="section">
          <section className="cta" aria-labelledby="cta-heading">
            <LogoMark size={56} />
            <h2 id="cta-heading">Ride with a little more awareness</h2>
            <p>Try the simulation, or explore the ride map.</p>
            <div className="cta__actions">
              <Link className="button button--primary" href="/simulation">
                See it in action
                <span aria-hidden="true"> →</span>
              </Link>
              <Link className="button button--ghost" href="/dashboard">
                Explore the ride map
              </Link>
            </div>
          </section>
        </Reveal>
      </div>
    </main>
  );
}

import Link from "next/link";

const features = [
  "Scan receipts and turn them into itemized splits.",
  "Split bills equally, unequally, by shares, or by item.",
  "Track balances, invite friends, and record settlements.",
  "Use multiple currencies for trips, dinners, and shared expenses.",
];

export default function Home() {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-4xl flex-col items-center justify-center px-6 py-16 text-center">
      <section className="w-full max-w-2xl space-y-8">
        <div className="space-y-4">
          <p className="text-sm font-medium uppercase tracking-[0.3em] text-zinc-500">
            Split bills with friends
          </p>
          <h1 className="text-5xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50 sm:text-6xl">
            PayUp
          </h1>
          <p className="mx-auto max-w-xl text-lg leading-8 text-zinc-600 dark:text-zinc-300">
            PayUp helps friends scan receipts, split shared expenses, track who
            owes what, and record settlements without doing friendship algebra.
          </p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          {features.map((feature) => (
            <div
              className="rounded-2xl border border-zinc-200 bg-white p-5 text-left text-sm leading-6 text-zinc-700 shadow-sm dark:border-zinc-800 dark:bg-zinc-950 dark:text-zinc-300"
              key={feature}
            >
              {feature}
            </div>
          ))}
        </div>

        <div className="rounded-3xl border border-dashed border-zinc-300 bg-zinc-50 p-8 text-sm text-zinc-500 dark:border-zinc-700 dark:bg-zinc-900/50 dark:text-zinc-400">
          App screenshots coming soon.
        </div>

        <p className="text-sm leading-6 text-zinc-500 dark:text-zinc-400">
          PayUp is an informal shared ledger for expenses and settlements. It
          does not move money or process payments.
        </p>

        <nav className="flex items-center justify-center gap-6 text-sm font-medium">
          <Link className="hover:underline" href="/privacy">
            Privacy Policy
          </Link>
          <Link className="hover:underline" href="/terms">
            Terms of Service
          </Link>
        </nav>
      </section>
    </main>
  );
}

import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "Terms of Service for PayUp.",
  alternates: {
    canonical: "/terms",
  },
};

const sections = [
  {
    title: "Using PayUp",
    body: [
      "PayUp helps friends keep an informal shared ledger of expenses, splits, balances, invitations, and settlement records. You may use PayUp only if you can form a binding agreement and only in compliance with these Terms and applicable law.",
      "You are responsible for the information you add to PayUp, including expense details, receipt images, participants, invited contacts, amounts, currencies, and settlement records.",
    ],
  },
  {
    title: "PayUp Does Not Move Money",
    body: [
      "PayUp is not a bank, payment processor, money transmitter, debt collector, escrow service, or financial institution. The app records expenses and settlements for your convenience, but it does not send, receive, hold, or transfer funds.",
      "Any payment or reimbursement you make outside PayUp is between you and the other person. PayUp is not responsible for outside payment services or for whether another person pays you back.",
    ],
  },
  {
    title: "Shared Expense Records",
    body: [
      "When you create or join shared expenses, related information may be visible to the people involved. This may include names, amounts, currencies, receipt details, split assignments, settlement records, activity updates, and edit history.",
      "You should only add people, receipts, and expense details that you have the right to share.",
    ],
  },
  {
    title: "Receipt Scanning",
    body: [
      "PayUp may use automated receipt analysis to extract merchant names, items, taxes, tips, totals, and other receipt details. Automated results may be incomplete or incorrect.",
      "You are responsible for reviewing and correcting receipt scan results before saving or sharing an expense.",
    ],
  },
  {
    title: "Accounts and Security",
    body: [
      "You are responsible for maintaining access to your account and for activity that occurs through your account. Tell us if you believe your account has been used without permission.",
      "You agree not to misuse PayUp, interfere with the service, attempt to access another user's account or data, send abusive invitations, upload unlawful content, or use PayUp for fraud or illegal activity.",
    ],
  },
  {
    title: "Third-Party Services",
    body: [
      "PayUp relies on third-party services for authentication, backend storage and sync, receipt analysis, exchange rates, sign-in providers, and push notifications. These services may change, fail, or be unavailable from time to time.",
      "Your use of third-party sign-in providers or any outside payment method is also subject to those providers' terms and policies.",
    ],
  },
  {
    title: "Service Changes and Availability",
    body: [
      "We may update, suspend, limit, or discontinue parts of PayUp at any time. We try to keep PayUp available, but we do not guarantee that the service will be uninterrupted, secure, or error-free.",
    ],
  },
  {
    title: "Intellectual Property",
    body: [
      "PayUp and its design, software, branding, and content are owned by PayUp or its licensors. These Terms do not give you ownership of PayUp or permission to copy, modify, distribute, sell, or reverse engineer the app except where permitted by law.",
      "You keep ownership of content you add to PayUp, but you give PayUp permission to host, process, display, and share that content as needed to provide the service.",
    ],
  },
  {
    title: "Disclaimers",
    body: [
      "PayUp is provided as is and as available. To the fullest extent permitted by law, we disclaim warranties of merchantability, fitness for a particular purpose, non-infringement, and any warranties arising from course of dealing or usage of trade.",
      "PayUp does not provide legal, tax, accounting, financial, or debt collection advice. Expense balances and settlement records are informal records between users.",
    ],
  },
  {
    title: "Limitation of Liability",
    body: [
      "To the fullest extent permitted by law, PayUp will not be liable for indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost profits, lost data, or disputes between users.",
      "To the fullest extent permitted by law, PayUp's total liability for any claim related to the service will be limited to the greater of the amount you paid to use PayUp in the 12 months before the claim or USD $100.",
    ],
  },
  {
    title: "Termination",
    body: [
      "You may stop using PayUp at any time. We may suspend or terminate access if we believe you violated these Terms, created risk for PayUp or other users, or used the service unlawfully.",
    ],
  },
  {
    title: "Changes to These Terms",
    body: [
      "We may update these Terms from time to time. If we make changes, we will update the effective date on this page. Your continued use of PayUp after changes become effective means you accept the updated Terms.",
    ],
  },
  {
    title: "Contact",
    body: ["For questions about these Terms, contact PayUp at createplus.club@gmail.com."],
  },
];

export default function TermsOfService() {
  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-12 sm:py-16">
      <Link className="text-sm font-medium hover:underline" href="/">
        Back to PayUp
      </Link>

      <header className="mt-10 space-y-4">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          Effective date: May 24, 2026
        </p>
        <h1 className="text-4xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
          Terms of Service
        </h1>
        <p className="text-base leading-7 text-zinc-600 dark:text-zinc-300">
          These Terms govern your use of the PayUp iOS app and website. By
          using PayUp, you agree to these Terms.
        </p>
      </header>

      <div className="mt-10 space-y-10">
        {sections.map((section) => (
          <section className="space-y-4" key={section.title}>
            <h2 className="text-2xl font-semibold tracking-tight">
              {section.title}
            </h2>
            <div className="space-y-3 text-base leading-7 text-zinc-700 dark:text-zinc-300">
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </div>
          </section>
        ))}
      </div>
    </main>
  );
}

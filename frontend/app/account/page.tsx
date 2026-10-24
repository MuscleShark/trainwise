"use client";

import { useClerk, useUser } from "@clerk/nextjs";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { UnauthorizedError, useApi } from "../lib/api";
import type { components } from "../lib/api-types";

type Account = components["schemas"]["UserRead"];

export default function AccountPage() {
  const { apiFetch, isReady } = useApi();
  const { signOut } = useClerk();
  const [account, setAccount] = useState<Account | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!isReady) return;

    async function loadAccount() {
      try {
        const response = await apiFetch("/me");
        if (!response.ok) throw new Error();
        setAccount(await response.json());
      } catch (loadError) {
        if (loadError instanceof UnauthorizedError) return;
        setError("Couldn't load your account. Check your connection and reload the page.");
      }
    }

    void loadAccount();
  }, [isReady, apiFetch]);

  return (
    <div className="flex flex-1 flex-col">
      <header className="mx-auto flex w-full max-w-3xl items-center justify-between px-4 py-6 sm:px-8">
        <Link href="/" className="type-stamp text-xl">
          IronSage
        </Link>
        <button
          type="button"
          onClick={() => void signOut({ redirectUrl: "/" })}
          className="rounded-md px-3 py-2 text-sm font-medium text-steel transition-colors hover:text-ink"
        >
          Sign out
        </button>
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 py-10 sm:px-8">
        <h1 className="type-stamp text-4xl">Account</h1>

        {error ? (
          <p role="alert" className="mt-8 rounded-sm border border-plate-red/30 bg-white/70 px-4 py-3 text-plate-red">
            {error}
          </p>
        ) : account ? (
          <>
            <p className="mt-6 text-lg">
              Signed in as <span className="font-semibold">{account.email}</span>
            </p>
            <p className="mt-2 max-w-xl leading-relaxed text-steel">
              Your training is logged in the IronSage iPhone app, coming soon.
            </p>
            <DeleteAccount />
          </>
        ) : (
          <p className="mt-6 text-steel">Loading your account…</p>
        )}
      </main>
    </div>
  );
}

// Deletes the IronSage data first, then the Clerk user. If the Clerk step fails the
// data is already gone, and signing in again starts an empty account.
function DeleteAccount() {
  const { apiFetch } = useApi();
  const { user } = useUser();
  const router = useRouter();
  const [isConfirming, setIsConfirming] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [error, setError] = useState("");

  async function deleteAccount() {
    setError("");
    setIsDeleting(true);

    try {
      const response = await apiFetch("/me", { method: "DELETE" });
      if (!response.ok) throw new Error("Couldn't delete your account. Try again.");
      await user?.delete();
      router.replace("/");
    } catch (deleteError) {
      if (deleteError instanceof UnauthorizedError) return;
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Couldn't reach IronSage. Check your connection and try again.",
      );
      setIsDeleting(false);
    }
  }

  return (
    <section className="mt-12 border-t border-ink/15 pt-8">
      <h2 className="text-xl font-semibold">Delete account</h2>
      <p className="mt-2 max-w-xl leading-relaxed text-steel">
        Permanently deletes your account, your profile and all of your workouts.
        This cannot be undone.
      </p>
      {error ? (
        <p role="alert" className="mt-4 text-plate-red">
          {error}
        </p>
      ) : null}
      {isConfirming ? (
        <div className="mt-6 flex flex-wrap gap-3">
          <button
            type="button"
            onClick={deleteAccount}
            disabled={isDeleting}
            className="rounded-sm bg-plate-red px-5 py-3 font-semibold text-white transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isDeleting ? "Deleting…" : "Yes, delete everything"}
          </button>
          <button
            type="button"
            onClick={() => setIsConfirming(false)}
            disabled={isDeleting}
            className="rounded-sm border border-ink/20 px-5 py-3 font-semibold transition-colors hover:border-ink/40"
          >
            Cancel
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => setIsConfirming(true)}
          className="mt-6 rounded-sm border border-plate-red/50 px-5 py-3 font-semibold text-plate-red transition-colors hover:border-plate-red"
        >
          Delete account
        </button>
      )}
    </section>
  );
}

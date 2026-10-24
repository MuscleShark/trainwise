import { clerkMiddleware } from "@clerk/nextjs/server";

// Keeps the Clerk session in sync on every request. Pages that need a signed-in
// user check it client-side (see app/lib/api.ts); the API verifies every token.
export default clerkMiddleware();

export const config = {
  matcher: [
    // Skip Next.js internals and static files, unless found in search params
    "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
    "/(api|trpc)(.*)",
  ],
};

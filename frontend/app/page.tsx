"use client";

import { useEffect, useState } from "react";

export default function Home() {
  const [message, setMessage] = useState("Loading...");

  useEffect(() => {
    async function fetchMessage() {
      try {
        const response = await fetch("http://localhost:8000/hello");

        if (!response.ok) {
          throw new Error("Failed to fetch backend");
        }

        const data = await response.json();
        setMessage(data.message);
      } catch (error) {
        console.error(error);
        setMessage("Could not connect to backend");
      }
    }

    fetchMessage();
  }, []);

  return (
    <main className="flex min-h-screen items-center justify-center">
      <h1 className="text-4xl font-bold">{message}</h1>
    </main>
  );
}
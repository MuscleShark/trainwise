import { SignIn } from "@clerk/nextjs";

import AuthShell from "../../components/AuthShell";

export default function LoginPage() {
  return (
    <AuthShell>
      <SignIn routing="path" path="/login" />
    </AuthShell>
  );
}

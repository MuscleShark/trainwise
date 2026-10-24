import { SignUp } from "@clerk/nextjs";

import AuthShell from "../../components/AuthShell";

export default function RegisterPage() {
  return (
    <AuthShell>
      <SignUp routing="path" path="/register" />
    </AuthShell>
  );
}

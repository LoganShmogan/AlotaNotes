import { SignUp } from "@clerk/nextjs";
import { AuthFrame } from "@/components/AuthFrame";

export const metadata = { title: "Create an account" };

export default function SignUpPage() {
  return (
    <AuthFrame>
      <SignUp fallbackRedirectUrl="/today" signInUrl="/sign-in" />
    </AuthFrame>
  );
}

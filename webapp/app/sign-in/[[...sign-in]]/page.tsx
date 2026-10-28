import { SignIn } from "@clerk/nextjs";
import { AuthFrame } from "@/components/AuthFrame";

export const metadata = { title: "Sign in" };

export default function SignInPage() {
  return (
    <AuthFrame>
      <SignIn fallbackRedirectUrl="/today" signUpUrl="/sign-up" />
    </AuthFrame>
  );
}

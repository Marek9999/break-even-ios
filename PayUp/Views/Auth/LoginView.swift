import SwiftUI
import Clerk
import AuthenticationServices

struct LoginView: View {
    @Environment(\.clerk) private var clerk

    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false
    @State private var showingEmailSignIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            OnboardingWelcomeView(
                onAppleTap: { Task { await signInWithApple() } },
                onGoogleTap: { Task { await signInWithGoogle() } },
                onEmailTap: { showingEmailSignIn = true }
            )

            if isAppleLoading || isGoogleLoading {
                loadingOverlay
            }

            if let errorMessage {
                errorBanner(errorMessage)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAppleLoading)
        .animation(.easeInOut(duration: 0.2), value: isGoogleLoading)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
        .sheet(isPresented: $showingEmailSignIn) {
            EmailSignInSheet(errorMessage: $errorMessage)
                .presentationDetents([.height(430), .medium])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Overlays

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.white)
        }
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.red.opacity(0.85), in: .rect(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .onTapGesture {
                    withAnimation { errorMessage = nil }
                }
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Auth Actions

    private func signInWithApple() async {
        isAppleLoading = true
        errorMessage = nil
        defer { isAppleLoading = false }

        do {
            let credential = try await SignInWithAppleHelper.getAppleIdCredential()
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Failed to get Apple ID token."
                return
            }
            let _ = try await SignIn.authenticateWithIdToken(
                provider: .apple,
                idToken: idToken
            )
        } catch let error as ASAuthorizationError where error.code == .canceled || error.code == .unknown {
            return
        } catch {
            errorMessage = clerkErrorMessage(error)
        }
    }

    private func signInWithGoogle() async {
        isGoogleLoading = true
        errorMessage = nil
        defer { isGoogleLoading = false }

        do {
            let _ = try await SignIn.authenticateWithRedirect(
                strategy: .oauth(provider: .google)
            )
        } catch {
            if (error as NSError).code == 1001 ||
               (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" {
                return
            }
            errorMessage = clerkErrorMessage(error)
        }
    }

    private func clerkErrorMessage(_ error: Error) -> String {
        if let clerkError = error as? ClerkAPIError {
            return clerkError.longMessage ?? clerkError.message ?? "An unknown error occurred."
        }
        return error.localizedDescription
    }
}

#Preview {
    LoginView()
}

import SwiftUI
import Clerk

struct EmailSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var errorMessage: String?

    @State private var email = ""
    @State private var password = ""
    @State private var localError: String?
    @State private var isSigningIn = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        trimmedEmail.contains("@") && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        ZStack {
            Color.homeSectionBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                headerRow

                VStack(alignment: .leading, spacing: 10) {
                    Text("Use the email and password attached to your Clerk account.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appText.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)

                    formFields
                }

                if let localError {
                    Text(localError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }

                signInButton

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedField = .email
        }
        .animation(.easeInOut(duration: 0.2), value: localError)
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Sign in with email")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appText)

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(isSigningIn)
        }
    }

    private var formFields: some View {
        VStack(spacing: 12) {
            TextField(
                "",
                text: $email,
                prompt: Text("Email").foregroundStyle(Color.appText.opacity(0.32))
            )
            .focused($focusedField, equals: .email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.next)
            .foregroundStyle(Color.appText)
            .onSubmit {
                focusedField = .password
            }
            .onChange(of: email) { _, _ in
                localError = nil
                errorMessage = nil
            }
            .authFieldStyle()

            SecureField(
                "",
                text: $password,
                prompt: Text("Password").foregroundStyle(Color.appText.opacity(0.32))
            )
            .focused($focusedField, equals: .password)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .submitLabel(.go)
            .foregroundStyle(Color.appText)
            .onSubmit {
                submitIfPossible()
            }
            .onChange(of: password) { _, _ in
                localError = nil
                errorMessage = nil
            }
            .authFieldStyle()
        }
    }

    private var signInButton: some View {
        Button {
            submitIfPossible()
        } label: {
            HStack(spacing: 8) {
                if isSigningIn {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                } else {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(Capsule())
            .glassEffect(.clear.tint(.white.opacity(canSubmit ? 0.9 : 0.4)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private func submitIfPossible() {
        guard canSubmit else { return }

        Task {
            await signInWithEmail()
        }
    }

    @MainActor
    private func signInWithEmail() async {
        isSigningIn = true
        localError = nil
        errorMessage = nil
        focusedField = nil

        defer { isSigningIn = false }

        do {
            var signIn = try await SignIn.create(
                strategy: .identifier(trimmedEmail, password: password)
            )

            if signIn.status == .needsFirstFactor,
               signIn.supportedFirstFactors?.contains(where: { $0.strategy == "password" }) == true {
                signIn = try await signIn.attemptFirstFactor(strategy: .password(password: password))
            }

            guard signIn.status == .complete else {
                localError = message(for: signIn.status)
                return
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            let message = clerkErrorMessage(error)
            localError = message
            errorMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func message(for status: SignIn.Status) -> String {
        switch status {
        case .needsSecondFactor, .needsClientTrust:
            "This account needs an additional verification step. Use a test account without MFA for App Store review."
        case .needsNewPassword:
            "This account needs a new password before it can sign in."
        case .needsIdentifier, .needsFirstFactor:
            "Email/password sign in is not available for this account."
        case .complete:
            ""
        case .unknown:
            "Sign in could not be completed. Please try again."
        }
    }

    private func clerkErrorMessage(_ error: Error) -> String {
        if let clerkError = error as? ClerkAPIError {
            return clerkError.longMessage ?? clerkError.message ?? "Sign in failed. Please try again."
        }
        return error.localizedDescription
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.body)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.white.opacity(0.05))
            .clipShape(Capsule())
    }
}

#Preview {
    EmailSignInSheet(errorMessage: .constant(nil))
}

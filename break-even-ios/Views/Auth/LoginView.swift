import SwiftUI
import Clerk
import AuthenticationServices

struct LoginView: View {
    @Environment(\.clerk) private var clerk
    
    @State private var email = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false
    @State private var errorMessage: String?
    @State private var signIn: SignIn?
    @State private var signUp: SignUp?
    @State private var showOTP = false
    
    @FocusState private var isEmailFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                heroImage
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    
                    VStack(spacing: 24) {
                        tagline
                        emailSection
                        orDivider
                        socialButtons
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                }
            }
            .background(Color.black)
            .onTapGesture {
                isEmailFocused = false
            }
            .navigationDestination(isPresented: $showOTP) {
                OTPVerificationView(signIn: $signIn, signUp: $signUp, email: email)
            }
        }
    }
    
    // MARK: - Hero Image
    
    private var heroImage: some View {
        Image("onBoarding")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 530)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Tagline
    
    private var tagline: some View {
        Text("Let the app do the maths,\nyou enjoy the drinks")
            .font(.title)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Email Section
    
    private var emailSection: some View {
        VStack(spacing: 16) {
            TextField("", text: $email, prompt:
                Text("Enter your email")
                    .foregroundStyle(Color(.systemGray))
            )
            .focused($isEmailFocused)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            Button {
                Task { await continueWithEmail() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
        }
    }
    
    // MARK: - Divider
    
    private var orDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
            Text("Or")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray))
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Social Buttons
    
    private var socialButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task { await signInWithApple() }
            } label: {
                Group {
                    if isAppleLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image("apple")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 24)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .buttonStyle(.glass)
            
            Button {
                Task { await signInWithGoogle() }
            } label: {
                Group {
                    if isGoogleLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image("google")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .buttonStyle(.glass)
        }
    }
    
    // MARK: - Auth Actions
    
    private func continueWithEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation { errorMessage = "Please enter your email address." }
            return
        }
        guard trimmed.isValidEmail else {
            withAnimation { errorMessage = "Please enter a valid email address." }
            return
        }
        
        signIn = nil
        signUp = nil
        showOTP = false
        
        withAnimation { errorMessage = nil }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await SignIn.create(
                strategy: .identifier(trimmed, strategy: .emailCode())
            )
            
            if result.status == .complete {
                return
            }
            
            signIn = result
            signUp = nil
            showOTP = true
        } catch let error as ClerkAPIError
            where error.code == "form_identifier_not_found" {
            do {
                var newSignUp = try await SignUp.create(
                    strategy: .standard(emailAddress: trimmed)
                )
                newSignUp = try await newSignUp.prepareVerification(strategy: .emailCode)
                
                if newSignUp.status == .complete {
                    return
                }
                
                signUp = newSignUp
                signIn = nil
                showOTP = true
            } catch {
                withAnimation { errorMessage = clerkErrorMessage(error) }
            }
        } catch {
            withAnimation {
                errorMessage = clerkErrorMessage(error)
            }
        }
    }
    
    private func signInWithApple() async {
        isAppleLoading = true
        withAnimation { errorMessage = nil }
        defer { isAppleLoading = false }
        
        do {
            let credential = try await SignInWithAppleHelper.getAppleIdCredential()
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                withAnimation { errorMessage = "Failed to get Apple ID token." }
                return
            }
            let _ = try await SignIn.authenticateWithIdToken(
                provider: .apple,
                idToken: idToken
            )
        } catch let error as ASAuthorizationError where error.code == .canceled || error.code == .unknown {
            return
        } catch {
            withAnimation {
                errorMessage = clerkErrorMessage(error)
            }
        }
    }
    
    private func signInWithGoogle() async {
        isGoogleLoading = true
        withAnimation { errorMessage = nil }
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
            withAnimation {
                errorMessage = clerkErrorMessage(error)
            }
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

import SwiftUI
import Clerk

struct OTPVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Binding var signIn: SignIn?
    @Binding var signUp: SignUp?
    let email: String
    
    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0
    @State private var verificationSucceeded = false
    
    @FocusState private var isCodeFocused: Bool
    
    private let codeLength = 6
    
    private var isSignUpFlow: Bool { signUp != nil }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 32) {
                header
                codeInput
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                verifyButton
                resendSection
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            isCodeFocused = true
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 12) {
            Text("Check your email")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("We sent a verification code to **\(email)**")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Code Input
    
    private var codeInput: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<codeLength, id: \.self) { index in
                    let character = characterAt(index)
                    
                    Text(character.map(String.init) ?? "")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    index == code.count ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isCodeFocused = true
            }
            
            TextField("", text: $code)
                .focused($isCodeFocused)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.prefix(codeLength)).filter(\.isNumber)
                    if filtered != code {
                        code = filtered
                    }
                    if code.count == codeLength {
                        Task { await verifyCode() }
                    }
                }
        }
    }
    
    // MARK: - Verify Button
    
    private var verifyButton: some View {
        Button {
            Task { await verifyCode() }
        } label: {
            Group {
                if isVerifying {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Verify")
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(code.count == codeLength ? Color.accentColor : Color.accentColor.opacity(0.4))
            .clipShape(Capsule())
        }
        .disabled(code.count != codeLength || isVerifying)
    }
    
    // MARK: - Resend Section
    
    private var resendSection: some View {
        HStack(spacing: 4) {
            Text("Didn't receive the code?")
                .font(.subheadline)
                .foregroundStyle(Color(.systemGray))
            
            if resendCooldown > 0 {
                Text("Resend in \(resendCooldown)s")
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemGray))
            } else {
                Button {
                    Task { await resendCode() }
                } label: {
                    if isResending {
                        ProgressView()
                            .tint(.accentColor)
                            .scaleEffect(0.8)
                    } else {
                        Text("Resend")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .disabled(isResending)
            }
        }
    }
    
    // MARK: - Actions
    
    private func characterAt(_ index: Int) -> Character? {
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }
    
    private func verifyCode() async {
        guard code.count == codeLength, !isVerifying, !verificationSucceeded else { return }
        
        isVerifying = true
        withAnimation { errorMessage = nil }
        
        do {
            if isSignUpFlow, var currentSignUp = signUp {
                currentSignUp = try await currentSignUp.attemptVerification(
                    strategy: .emailCode(code: code)
                )
                
                if currentSignUp.status == .missingRequirements {
                    currentSignUp = try await currentSignUp.update(
                        params: .init(firstName: "App", lastName: "User")
                    )
                }
                
                verificationSucceeded = true
                signUp = currentSignUp
                
                if currentSignUp.status != .complete {
                    isVerifying = false
                    withAnimation {
                        errorMessage = "Account setup is incomplete. Missing: \(currentSignUp.missingFields.joined(separator: ", "))"
                    }
                    return
                }
            } else if var currentSignIn = signIn {
                currentSignIn = try await currentSignIn.attemptFirstFactor(
                    strategy: .emailCode(code: code)
                )
                verificationSucceeded = true
                signIn = currentSignIn
                
                if currentSignIn.status != .complete {
                    isVerifying = false
                    withAnimation {
                        errorMessage = "Additional verification is required. Status: \(currentSignIn.status)"
                    }
                    return
                }
            }
            
            // Sign-in/sign-up is complete. The Clerk SDK updates clerk.session
            // synchronously before attemptFirstFactor returns, so RootView
            // should already be transitioning to MainTabView. Keep the spinner
            // visible as a brief transition state.
        } catch {
            isVerifying = false
            verificationSucceeded = false
            withAnimation {
                if let clerkError = error as? ClerkAPIError {
                    errorMessage = clerkError.longMessage ?? clerkError.message ?? "An unknown error occurred."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            code = ""
        }
    }
    
    private func resendCode() async {
        isResending = true
        withAnimation { errorMessage = nil }
        defer { isResending = false }
        
        do {
            if isSignUpFlow, var currentSignUp = signUp {
                currentSignUp = try await currentSignUp.prepareVerification(strategy: .emailCode)
                signUp = currentSignUp
            } else if var currentSignIn = signIn {
                currentSignIn = try await currentSignIn.prepareFirstFactor(strategy: .emailCode())
                signIn = currentSignIn
            }
            verificationSucceeded = false
            startResendCooldown()
        } catch {
            withAnimation {
                if let clerkError = error as? ClerkAPIError {
                    errorMessage = clerkError.longMessage ?? clerkError.message ?? "An unknown error occurred."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func startResendCooldown() {
        resendCooldown = 30
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendCooldown > 0 {
                resendCooldown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

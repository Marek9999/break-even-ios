import SwiftUI
import Clerk
import ConvexMobile
internal import Combine

struct UsernameSetupView: View {
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    var onComplete: () -> Void
    
    @State private var username = ""
    @State private var isChecking = false
    @State private var isSubmitting = false
    @State private var availability: UsernameAvailabilityResponse?
    @State private var errorMessage: String?
    @State private var checkTask: Task<Void, Never>?
    
    @FocusState private var isFocused: Bool
    
    private var trimmedUsername: String {
        username.lowercased().trimmingCharacters(in: .whitespaces)
    }
    
    private var isValid: Bool {
        trimmedUsername.count >= 3 && trimmedUsername.count <= 20
        && trimmedUsername.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil
    }
    
    private var canSubmit: Bool {
        isValid && availability?.available == true && !isSubmitting
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "at")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.accent)
                
                VStack(spacing: 8) {
                    Text("Choose a Username")
                        .font(.title.bold())
                    
                    Text("Your friends will use this to find and invite you on BreakEven.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("@")
                            .font(.title3.monospaced())
                            .foregroundStyle(.secondary)
                        
                        TextField("username", text: $username)
                            .font(.title3.monospaced())
                            .textContentType(.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isFocused)
                            .onChange(of: username) { _, newValue in
                                username = newValue.lowercased().filter {
                                    $0.isLetter || $0.isNumber || $0 == "_"
                                }
                                if username.count > 20 {
                                    username = String(username.prefix(20))
                                }
                                availability = nil
                                errorMessage = nil
                                debounceCheck()
                            }
                            .onSubmit {
                                if canSubmit { submitUsername() }
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack(spacing: 6) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking availability...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let availability {
                            if availability.available {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Available!")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(availability.reason ?? "Not available")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        } else if !username.isEmpty && !isValid {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("3-20 characters, letters, numbers, underscores only")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(height: 20)
                    .animation(.easeInOut(duration: 0.2), value: isChecking)
                    .animation(.easeInOut(duration: 0.2), value: availability?.available)
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                submitUsername()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!canSubmit)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear { isFocused = true }
    }
    
    private func debounceCheck() {
        checkTask?.cancel()
        
        guard isValid else {
            isChecking = false
            return
        }
        
        isChecking = true
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            
            let subscription = convexService.client.subscribe(
                to: "users:checkUsernameAvailable",
                with: ["username": trimmedUsername],
                yielding: UsernameAvailabilityResponse.self
            )
            .replaceError(with: UsernameAvailabilityResponse(available: false, reason: "Check failed"))
            .values
            
            for await result in subscription {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    availability = result
                    isChecking = false
                }
                break
            }
        }
    }
    
    private func submitUsername() {
        guard let clerkId = clerk.user?.id, canSubmit else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                let _: SetUsernameResponse = try await convexService.client.mutation(
                    "users:setUsername",
                    with: [
                        "clerkId": clerkId,
                        "username": trimmedUsername,
                    ]
                )
                
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    isSubmitting = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    UsernameSetupView(onComplete: {})
}

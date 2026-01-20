//
//  AddPersonSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import Clerk
import ConvexMobile

/// Sheet for adding a new person/contact
struct AddPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clerk) private var clerk
    @Environment(\.convexService) private var convexService
    
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isLoading = false
    @State private var error: String?
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, phone
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .email
                        }
                } header: {
                    Text("Required")
                }
                
                Section {
                    TextField("Email", text: $email)
                        .focused($focusedField, equals: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .phone
                        }
                    
                    TextField("Phone", text: $phone)
                        .focused($focusedField, equals: .phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Optional")
                } footer: {
                    Text("Contact info helps identify this person later.")
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Add") {
                            addPerson()
                        }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                    }
                }
            }
            .onAppear {
                focusedField = .name
            }
            .interactiveDismissDisabled(isLoading)
        }
    }
    
    private func addPerson() {
        guard let clerkId = clerk.user?.id else {
            error = "Not authenticated"
            return
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        Task {
            do {
                // Build args - only include optional fields if they have values
                var args: [String: String] = [
                    "clerkId": clerkId,
                    "name": trimmedName
                ]
                if !email.isEmpty {
                    args["email"] = email
                }
                if !phone.isEmpty {
                    args["phone"] = phone
                }
                
                let _: String = try await convexService.client.mutation(
                    "friends:createDummyFriend",
                    with: args
                )
                
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to add person: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AddPersonSheet()
}

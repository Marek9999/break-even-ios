//
//  PaidByPickerSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-18.
//

import SwiftUI
import UIKit

// MARK: - Wheel Picker Configuration

private enum FriendWheelConfig {
    static let rowHeight: CGFloat = 50
    static let avatarSize: CGFloat = 32
    static let avatarNameSpacing: CGFloat = 12
    static let nameFontSize: CGFloat = 20
    static let contentWidth: CGFloat = 240
}

// MARK: - UIKit Wheel Picker

struct FriendWheelPicker: UIViewRepresentable {
    let friends: [ConvexFriend]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        if let index = friends.firstIndex(where: { $0.id == selection }) {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        guard let index = friends.firstIndex(where: { $0.id == selection }) else { return }
        let current = picker.selectedRow(inComponent: 0)
        if current != index {
            picker.selectRow(index, inComponent: 0, animated: true)
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: FriendWheelPicker

        init(_ parent: FriendWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.friends.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            FriendWheelConfig.rowHeight
        }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            guard row < parent.friends.count else { return view ?? UIView() }
            let friend = parent.friends[row]

            if let existing = view as? FriendRowView {
                existing.update(with: friend)
                return existing
            }
            return FriendRowView(friend: friend)
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard row < parent.friends.count else { return }
            parent.selection = parent.friends[row].id
        }
    }
}

// MARK: - Friend Row View

/// Custom UIPickerView row that hosts a SwiftUI `FriendAvatar` plus a
/// truncating UILabel for the display name. Owns its `UIHostingController`
/// so the SwiftUI view stays alive while the row is on screen.
private final class FriendRowView: UIView {
    private let avatarHost: UIHostingController<FriendAvatar>
    private let nameLabel = UILabel()

    init(friend: ConvexFriend) {
        self.avatarHost = UIHostingController(rootView: FriendAvatar(friend: friend, size: FriendWheelConfig.avatarSize))
        super.init(frame: .zero)
        setupLayout()
        update(with: friend)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        avatarHost.view.backgroundColor = .clear
        avatarHost.view.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: FriendWheelConfig.nameFontSize, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(avatarHost.view)
        content.addSubview(nameLabel)
        addSubview(content)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: FriendWheelConfig.contentWidth),
            content.heightAnchor.constraint(equalTo: heightAnchor),

            avatarHost.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            avatarHost.view.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            avatarHost.view.widthAnchor.constraint(equalToConstant: FriendWheelConfig.avatarSize),
            avatarHost.view.heightAnchor.constraint(equalToConstant: FriendWheelConfig.avatarSize),

            nameLabel.leadingAnchor.constraint(equalTo: avatarHost.view.trailingAnchor, constant: FriendWheelConfig.avatarNameSpacing),
            nameLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    func update(with friend: ConvexFriend) {
        avatarHost.rootView = FriendAvatar(friend: friend, size: FriendWheelConfig.avatarSize)
        nameLabel.text = friend.displayName
    }
}

// MARK: - Sheet

/// Wheel-style "Paid by" picker. The caller supplies the list of candidate
/// payers (typically self + the friends added to the split). Uses the
/// draft-commit pattern so users can scroll through options without mutating
/// the bound payer until they tap "Select".
struct PaidByPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let participants: [ConvexFriend]
    @Binding var selectedFriend: ConvexFriend?

    @State private var currentId: String

    init(participants: [ConvexFriend], selectedFriend: Binding<ConvexFriend?>) {
        self.participants = participants
        self._selectedFriend = selectedFriend

        let initialId = selectedFriend.wrappedValue?.id
            ?? participants.first?.id
            ?? ""
        self._currentId = State(initialValue: initialId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if participants.isEmpty {
                    ContentUnavailableView(
                        "No People",
                        systemImage: "person.2",
                        description: Text("Add at least one person to the split first.")
                    )
                } else {
                    FriendWheelPicker(friends: participants, selection: $currentId)
                }
            }
            .navigationTitle("Paid by")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            // Make sure the bound payer matches whatever the wheel is showing
            // up front, so a swipe-down dismiss without scrolling still
            // commits the visible row (e.g. self when paidBy was nil).
            commitCurrentSelection()
        }
        .onChange(of: currentId) { _, _ in
            commitCurrentSelection()
        }
    }

    private func commitCurrentSelection() {
        guard let chosen = participants.first(where: { $0.id == currentId }) else { return }
        if selectedFriend?.id != chosen.id {
            selectedFriend = chosen
        }
    }
}

#if DEBUG
#Preview("Paid By Picker") {
    PaidByPickerSheet(
        participants: [.previewSelf, .previewAlice, .previewBob],
        selectedFriend: .constant(.previewSelf)
    )
}
#endif

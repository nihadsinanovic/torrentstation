import SwiftUI

struct AddTaskView: View {
    @Bindable var viewModel: AddTaskViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)

                        Text("Add Download")
                            .font(.title2.bold())

                        Text("Paste a magnet link or download URL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Input Area
                    TextEditor(text: $viewModel.inputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                        .focused($isInputFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    // Destination Picker
                    Button {
                        viewModel.showFolderPicker = true
                    } label: {
                        HStack {
                            Label("Destination", systemImage: "folder")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(viewModel.selectedDestinationName ?? "Not selected")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(.ultraThinMaterial)
                        )
                    }

                    // Feedback
                    if let success = viewModel.successMessage {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.completed)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Submit Button
                    Button {
                        isInputFocused = false
                        Task { await viewModel.submitTask() }
                    } label: {
                        Group {
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Start Download", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(!viewModel.canSubmit)
                }
                .padding(.horizontal, Theme.paddingLarge)
                .frame(maxWidth: 600)
            }
            .navigationTitle("Add")
            .animation(.default, value: viewModel.successMessage)
            .animation(.default, value: viewModel.errorMessage)
            .sheet(isPresented: $viewModel.showFolderPicker) {
                FolderPickerView(
                    fsService: viewModel.fsService,
                    recentDestinations: viewModel.recentDestinations
                ) { path, name in
                    viewModel.selectedDestination = path
                    viewModel.selectedDestinationName = name
                    // Also save to recents when user picks a folder
                    if let path, let name {
                        viewModel.addRecentDestination(path: path, name: name)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

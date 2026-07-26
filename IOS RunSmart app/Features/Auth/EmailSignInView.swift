import SwiftUI

/// Email sign-in sheet — the path in for anyone Sign in with Apple cannot serve.
struct EmailSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EmailSignInModel
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    init(model: @autoclosure @escaping () -> EmailSignInModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RunSmartBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        if model.phase == .confirmationRequired {
                            confirmationContent
                        } else {
                            formContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .preferredColorScheme(.dark)
            .navigationTitle(model.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Color.lime)
                }
            }
        }
    }

    private var formContent: some View {
        VStack(spacing: 22) {
            Picker("Mode", selection: modeBinding) {
                ForEach(EmailSignInModel.Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                TextField("Email", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .fieldStyle()

                SecureField("Password", text: $model.password)
                    // `.password` on sign-in and `.newPassword` on create is what
                    // lets the system offer to fill an existing credential in one
                    // case and generate a strong one in the other.
                    .textContentType(model.mode == .signIn ? .password : .newPassword)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit() } }
                    .fieldStyle()
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if model.mode == .createAccount {
                Text("At least \(EmailSignInModel.minimumPasswordLength) characters.")
                    .font(.caption2)
                    .foregroundStyle(Color.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                focusedField = nil
                Task { await model.submit() }
            } label: {
                Group {
                    if model.isSubmitting {
                        ProgressView().tint(.black)
                    } else {
                        Text(model.mode.title).fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .background(model.canSubmit ? Color.lime : Color.lime.opacity(0.35))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!model.canSubmit)

            Text("Your plan and runs sync to this account, so they survive a reinstall.")
                .font(.caption2)
                .foregroundStyle(Color.mutedText)
                .multilineTextAlignment(.center)
        }
    }

    private var confirmationContent: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.lime)
                .padding(.top, 12)

            Text("Confirm your email")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("We sent a confirmation link to \(model.normalizedEmail). "
                 + "Tap it, then come back and sign in.")
                .font(.subheadline)
                .foregroundStyle(Color.mutedText)
                .multilineTextAlignment(.center)

            Button {
                model.switchMode(to: .signIn)
            } label: {
                Text("Back to sign in")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .background(Color.lime)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var modeBinding: Binding<EmailSignInModel.Mode> {
        Binding(
            get: { model.mode },
            set: { model.switchMode(to: $0) }
        )
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .foregroundStyle(.white)
            .tint(Color.lime)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline, lineWidth: 0.5))
    }
}

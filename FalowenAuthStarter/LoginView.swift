
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Falowen Sign In").font(.title.bold())

            TextField("Email", text: $email)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding().background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding().background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Sign In") {
                Task { await auth.login(email: email, password: password) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty)

            if let err = auth.errorMessage {
                Text(err).foregroundColor(.red).font(.footnote)
            }
        }
        .padding()
    }
}

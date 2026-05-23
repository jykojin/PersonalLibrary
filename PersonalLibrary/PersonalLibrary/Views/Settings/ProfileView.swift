import SwiftUI

/// 用户登录 / 个人资料视图
struct ProfileView: View {
    @State private var authService = AuthService.shared
    @State private var isLoggingIn = false
    @State private var showingLoginError = false
    @State private var loginErrorMessage = ""

    var body: some View {
        Group {
            if authService.isLoggedIn, let user = authService.currentUser {
                loggedInView(user: user)
            } else {
                loggedOutView
            }
        }
    }

    // MARK: - Logged In

    private func loggedInView(user: UserProfile) -> some View {
        VStack(spacing: 20) {
            // 头像
            if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    case .failure:
                        defaultAvatar
                    case .empty:
                        ProgressView()
                            .frame(width: 80, height: 80)
                    @unknown default:
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }

            // 昵称
            Text(user.nickname)
                .font(.title3)
                .fontWeight(.medium)

            // 登录时间
            Text("登录于 \(formattedDate(user.loginDate))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)

            // 退出登录按钮
            Button(role: .destructive) {
                authService.logout()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Logged Out

    private var loggedOutView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("登录后可同步您的书架数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await loginWithWeChat() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                        .foregroundStyle(.white)
                    Text("微信登录")
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isLoggingIn)

            if isLoggingIn {
                ProgressView("正在登录...")
                    .font(.caption)
            }
        }
        .padding()
        .alert("登录失败", isPresented: $showingLoginError) {
            Button("好的") {}
        } message: {
            Text(loginErrorMessage)
        }
    }

    // MARK: - Private

    private var defaultAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 80, height: 80)
            .foregroundStyle(.secondary)
    }

    private func loginWithWeChat() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let code = try await WeChatAuthManager.shared.requestAuth()
            try await authService.loginWithWeChat(code: code)
        } catch let error as WeChatAuthError {
            loginErrorMessage = error.localizedDescription
            showingLoginError = true
        } catch {
            loginErrorMessage = error.localizedDescription
            showingLoginError = true
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview("已登录") {
    ProfileView()
}

#Preview("未登录") {
    ProfileView()
}

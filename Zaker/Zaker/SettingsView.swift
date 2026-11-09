import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(Prefs.uiLangKey) private var uiLang = "ar"
    @AppStorage(Prefs.outLangKey) private var outLang = "auto"
    @AppStorage(Prefs.modelKey) private var model = Prefs.defaultModel
    @State private var keyInput = ""
    @State private var hasKey = !Keychain.get().isEmpty
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("اللغة", "Language")) {
                    Picker(tr("لغة التطبيق", "App language"), selection: $uiLang) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                    Picker(tr("لغة الاختبارات والملخصات", "Quizzes & summaries language"), selection: $outLang) {
                        Text(tr("نفس لغة الكتاب", "Same as the book")).tag("auto")
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                }

                Section {
                    if hasKey {
                        Label(tr("المفتاح محفوظ ✓", "Key saved ✓"), systemImage: "key.fill")
                            .foregroundStyle(.green)
                        Button(tr("تجربة المفتاح", "Test key"), action: test)
                            .disabled(testing)
                        Button(tr("حذف المفتاح", "Remove key"), role: .destructive) {
                            Keychain.set("")
                            hasKey = false
                            testResult = nil
                        }
                    } else {
                        SecureField(tr("الصق مفتاح Gemini هنا", "Paste your Gemini API key"), text: $keyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(tr("حفظ المفتاح", "Save key")) {
                            Keychain.set(keyInput)
                            keyInput = ""
                            hasKey = !Keychain.get().isEmpty
                            if hasKey { test() }
                        }
                        .disabled(keyInput.trimmingCharacters(in: .whitespaces).count < 10)
                    }
                    if testing {
                        HStack { ProgressView(); Text(tr("نجرب…", "Testing…")) }
                    }
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(testOK ? .green : .red)
                    }
                } header: {
                    Text(tr("مفتاح Gemini", "Gemini API key"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("تاخذه مجانًا من Google AI Studio: سجّل دخول بحساب Google، واضغط Create API key، وانسخه هنا. المفتاح يبقى محفوظ في جوالك بس.",
                                "Get one free from Google AI Studio: sign in with Google, tap “Create API key”, and paste it here. The key stays on your phone."))
                        Link("aistudio.google.com/apikey", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    }
                }

                Section {
                    Picker(tr("الموديل", "Model"), selection: $model) {
                        Text("Gemini 3.8 Flash").tag("gemini-3.8-flash")
                        Text("Gemini 3.6 Flash").tag("gemini-3.6-flash")
                        Text("Gemini 2.5 Flash-Lite").tag("gemini-2.5-flash-lite")
                        if !["gemini-3.8-flash", "gemini-3.6-flash", "gemini-2.5-flash-lite"].contains(model) {
                            Text(model).tag(model)
                        }
                    }
                    TextField(tr("أو اكتب اسم موديل", "Or type a model name"), text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } header: {
                    Text(tr("الذكاء الاصطناعي", "AI model"))
                } footer: {
                    Text(tr("إذا طلع لك خطأ إن الموديل غير موجود أو وصلت الحد، جرّب موديل ثاني.",
                            "If you get a ‘model not found’ or limit error, try another model."))
                }

                Section {
                    HStack {
                        Text(tr("ذاكر", "Zaker"))
                        Spacer()
                        Text("1.0").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(tr("كتبك وملاحظاتك محفوظة على جوالك. الـAI يستلم الكتاب بس لما تطلب اختبار أو ملخص أو تسأل.",
                            "Your books and notes stay on your phone. The book is only sent to the AI when you ask for a quiz, summary or answer."))
                }
            }
            .navigationTitle(tr("الإعدادات", "Settings"))
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                let c = try AI.client()
                let reply = try await c.generate(contents: [["role": "user", "parts": [["text": "Reply with the single word: OK"]]]],
                                                 system: nil, schema: nil)
                testOK = true
                testResult = tr("المفتاح شغّال ✅ ", "Key works ✅ ") + "(\(Prefs.model)) " + String(reply.prefix(20))
            } catch {
                testOK = false
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}

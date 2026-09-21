import MiVibeCore
import SwiftUI

/// 改写模式提示词编辑。两个用途：
/// - 自定义模式：名称与 prompt 都可改，可删除；
/// - 内置模式：名称固定只读，只调 prompt，保存为用户覆盖，「恢复默认」删掉覆盖。
struct CustomModeEditor: View {
    let draft: RewriteMode
    var title: String? = nil
    var nameEditable = true
    var deleteLabel = "删除"
    let onSave: (RewriteMode) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var name: String
    @State private var prompt: String

    init(draft: RewriteMode, title: String? = nil, nameEditable: Bool = true,
         deleteLabel: String = "删除", onSave: @escaping (RewriteMode) -> Void,
         onDelete: (() -> Void)?, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.title = title
        self.nameEditable = nameEditable
        self.deleteLabel = deleteLabel
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _prompt = State(initialValue: draft.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title ?? (draft.name.isEmpty ? "新建自定义模式" : "编辑自定义模式"))
                .font(.headline)

            LabeledContent("名称:") {
                TextField("例如：邮件语气", text: $name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!nameEditable)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("处理指令:")
                    .font(.callout)
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .frame(minHeight: 160)
                    .border(Color.secondary.opacity(0.3))
                Text("系统会自动附加「只输出处理后的文本」的约束，这里只需描述想要的处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let onDelete {
                    Button(deleteLabel, role: .destructive) { onDelete() }
                }
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") {
                    onSave(RewriteMode(id: draft.id, name: name, prompt: prompt))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

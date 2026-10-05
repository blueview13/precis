import SwiftUI

struct SmartCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var mode: SmartCategoryMatchMode
    @State private var rules: [SmartCategoryRule]
    @State private var errorMessage: String?
    let existing: SmartCategory?
    let onSave: (SmartCategory) -> Void
    @FocusState private var nameFocused: Bool

    init(category: SmartCategory? = nil, onSave: @escaping (SmartCategory) -> Void) {
        existing = category; self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
        _mode = State(initialValue: category?.matchMode ?? .all)
        let savedRules: [SmartCategoryRule] = category?.rootGroup.children.compactMap { condition -> SmartCategoryRule? in
            if case .rule(let rule) = condition { return rule }
            return nil
        } ?? []
        _rules = State(initialValue: savedRules.isEmpty ? [SmartCategoryRule()] : savedRules)
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rules.contains {
            $0.field == .readStatus || ($0.field == .starred ? ["yes", "no"].contains($0.value) : !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Smart Category name:"); TextField("", text: $name).focused($nameFocused).frame(width: 260) }
            HStack {
                Text("Article matches")
                Picker("Match", selection: $mode) { Text("all").tag(SmartCategoryMatchMode.all); Text("any").tag(SmartCategoryMatchMode.any) }.labelsHidden().frame(width: 90)
                Text("of the following conditions")
                Spacer()
                Button { rules.append(SmartCategoryRule()) } label: { Image(systemName: "plus") }.help("Add condition")
            }
            ForEach($rules) { $rule in ruleRow(rule: $rule) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave) }
        }
        .padding(22)
        .frame(minWidth: 650, minHeight: 250)
        .onAppear { DispatchQueue.main.async { nameFocused = true } }
    }

    @ViewBuilder private func ruleRow(rule: Binding<SmartCategoryRule>) -> some View {
        HStack {
            Picker("Field", selection: rule.field) { ForEach(SmartCategoryField.allCases) { field in Text(field.label).tag(field) } }.labelsHidden().frame(width: 150)
                .onChange(of: rule.field.wrappedValue) { _, field in
                    rule.operation.wrappedValue = field.operators[0]
                    rule.value.wrappedValue = field == .starred ? "yes" : ""
                }
            Picker("Operator", selection: rule.operation) { ForEach(rule.field.wrappedValue.operators) { operation in Text(operation.label).tag(operation) } }.labelsHidden().frame(width: 190)
            if rule.field.wrappedValue == .readStatus {
                Text(" ").frame(maxWidth: .infinity)
            } else if rule.field.wrappedValue == .starred {
                Picker("Value", selection: rule.value) { Text("yes").tag("yes"); Text("no").tag("no") }.labelsHidden().frame(width: 120)
            } else {
                TextField(rule.field.wrappedValue == .publishedDate && rule.operation.wrappedValue == .inLastDays ? "Days" : rule.field.wrappedValue == .publishedDate ? "YYYY-MM-DD" : "Value", text: rule.value).textFieldStyle(.roundedBorder)
            }
            Button { if rules.count > 1, let index = rules.firstIndex(where: { $0.id == rule.wrappedValue.id }) { rules.remove(at: index) } } label: { Image(systemName: "minus") }.disabled(rules.count <= 1)
            Button { rules.append(SmartCategoryRule()) } label: { Image(systemName: "plus") }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = SmartCategoryStore.shared.categories.filter { !$0.isDeleted }
        guard !current.contains(where: { $0.id != existing?.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A Smart Category with that name already exists."; return
        }
        let preservedGroups = existing?.rootGroup.children.filter { if case .group = $0 { true } else { false } } ?? []
        let root = SmartCategoryRuleGroup(matchMode: mode, children: rules.map { .rule($0) } + preservedGroups)
        onSave(SmartCategory(id: existing?.id ?? UUID(), name: trimmed, colorHex: existing?.colorHex, matchMode: mode, rootGroup: root, sortOrder: existing?.sortOrder ?? current.count, createdAt: existing?.createdAt ?? Date()))
        dismiss()
    }
}

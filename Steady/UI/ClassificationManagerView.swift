import SwiftUI

struct ClassificationManagerView: View {
    @ObservedObject var localStore: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingRule: URLRule?
    @State private var editProjectName = ""
    @State private var editCategory: URLCategory = .unknown

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Site Classifications")
                    .font(.headline)
                Spacer()
                Text("\(localStore.urlRules.count) rules")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle")
                        .font(.body)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if localStore.urlRules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No classifications yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Sites are automatically classified as you browse during sessions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                List {
                    ForEach(localStore.urlRules.sorted { $0.domain < $1.domain }) { rule in
                        ruleRow(rule)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 480)
        .sheet(item: $editingRule) { rule in
            editSheet(for: rule)
        }
    }

    private func ruleRow(_ rule: URLRule) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.domain)
                    .font(.system(size: 13, weight: .medium))
                Text(rule.projectName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(rule.category.displayName)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(4)
            Button {
                editProjectName = rule.projectName
                editCategory = rule.category
                editingRule = rule
            } label: {
                Image(systemName: "pencil").font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
            Button {
                localStore.deleteURLRule(rule.id)
            } label: {
                Image(systemName: "trash").font(.caption).foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }

    private func editSheet(for rule: URLRule) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit: \(rule.domain)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Project").font(.caption).foregroundColor(.secondary)
                TextField("Project name", text: $editProjectName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $editCategory) {
                    ForEach(URLCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName.isEmpty ? cat.rawValue : cat.displayName).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { editingRule = nil }
                Spacer()
                Button("Save") {
                    var updated = rule
                    updated.projectName = editProjectName
                    updated.category = editCategory
                    updated.updatedAt = Date()
                    localStore.save(urlRule: updated)
                    editingRule = nil
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(editProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

import SwiftUI

struct TaskProgressView: View {
    let tasks: [String: TaskEvent]
    var onStopTask: ((String) -> Void)?

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sortedTasks, id: \.taskID) { task in
                    taskRow(task)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.blue.opacity(0.2), lineWidth: 0.5)
            )
        }
    }

    private var sortedTasks: [TaskEvent] {
        tasks.values.sorted { $0.taskID < $1.taskID }
    }

    private func taskRow(_ task: TaskEvent) -> some View {
        HStack(spacing: 6) {
            statusIcon(task.status)

            VStack(alignment: .leading, spacing: 1) {
                Text("Sub-agent task")
                    .font(.caption)
                    .fontWeight(.medium)

                if let summary = task.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if task.status == .started || task.status == .inProgress, let onStop = onStopTask {
                Button {
                    onStop(task.taskID)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            Text(task.status.label)
                .font(.caption2)
                .foregroundStyle(statusColor(task.status))
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: TaskStatus) -> some View {
        switch status {
        case .started, .inProgress:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .stopped:
            Image(systemName: "stop.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .started, .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .stopped: .orange
        }
    }
}

extension TaskStatus {
    var label: String {
        switch self {
        case .started: "Starting..."
        case .inProgress: "Running..."
        case .completed: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }
}

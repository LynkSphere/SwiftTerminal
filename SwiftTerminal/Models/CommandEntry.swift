import Foundation
import Observation

@Observable
final class CommandEntry: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var command: String
    var isDefault: Bool

    @ObservationIgnored
    weak var workspace: Workspace?

    var runner: CommandRunner {
        CommandRunner.runner(for: id)
    }

    init(workspace: Workspace, name: String, command: String) {
        self.id = UUID()
        self.workspace = workspace
        self.name = name
        self.command = command
        self.isDefault = false
    }

    func run() {
        guard let workspace else { return }
        runner.run(command: command, in: workspace.url)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, command, isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.command = try c.decode(String.self, forKey: .command)
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encode(isDefault, forKey: .isDefault)
    }

    // MARK: - Hashable

    static func == (lhs: CommandEntry, rhs: CommandEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

import Foundation

struct MatchRowViewModelMapper {
    private let dateFormatter: DateFormatter
    private let oddsFormatter: NumberFormatter

    init(
        dateFormatter: DateFormatter? = nil,
        oddsFormatter: NumberFormatter? = nil
    ) {
        self.dateFormatter = dateFormatter ?? MatchRowViewModelMapper.makeDateFormatter()
        self.oddsFormatter = oddsFormatter ?? MatchRowViewModelMapper.makeOddsFormatter()
    }

    func makeRows(from records: [MatchRecord]) -> [MatchRowViewModel] {
        records.map(makeRow)
    }

    private func makeRow(from record: MatchRecord) -> MatchRowViewModel {
        MatchRowViewModel(
            matchID: record.matchID,
            title: "\(record.teamA) vs \(record.teamB)",
            startTimeText: dateFormatter.string(from: record.startTime),
            oddsText: makeOddsText(from: record.oddsState)
        )
    }

    private func makeOddsText(from oddsState: OddsState) -> String {
        switch oddsState {
        case let .available(teamAOdds, teamBOdds):
            return "\(formatOdds(teamAOdds)) - \(formatOdds(teamBOdds))"
        case .unavailable:
            return "--"
        }
    }

    private func formatOdds(_ odds: Decimal) -> String {
        oddsFormatter.string(from: odds as NSDecimalNumber) ?? "--"
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }

    private static func makeOddsFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter
    }
}

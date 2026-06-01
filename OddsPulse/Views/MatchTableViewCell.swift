import UIKit

final class MatchTableViewCell: UITableViewCell {
    static let reuseIdentifier = "MatchTableViewCell"

    private enum Layout {
        static let teamColumnWidthMultiplier = 0.3
    }

    private let teamALabel = UILabel()
    private let teamBLabel = UILabel()
    private let startTimeLabel = UILabel()
    private let teamAOddsLabel = UILabel()
    private let teamBOddsLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with row: MatchRowViewModel) {
        teamALabel.text = row.teamA
        teamBLabel.text = row.teamB
        startTimeLabel.text = row.startTimeText
        teamAOddsLabel.text = row.teamAOddsText
        teamBOddsLabel.text = row.teamBOddsText
    }

    private func configureView() {
        selectionStyle = .none
        accessoryType = .none

        configureTeamLabel(teamALabel)
        configureTeamLabel(teamBLabel)
        configureOddsLabel(teamAOddsLabel)
        configureOddsLabel(teamBOddsLabel)

        startTimeLabel.font = .preferredFont(forTextStyle: .subheadline)
        startTimeLabel.textColor = .secondaryLabel
        startTimeLabel.textAlignment = .right
        startTimeLabel.adjustsFontForContentSizeCategory = true
        startTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let teamAStackView = makeTeamStackView(teamLabel: teamALabel, oddsLabel: teamAOddsLabel)
        let teamBStackView = makeTeamStackView(teamLabel: teamBLabel, oddsLabel: teamBOddsLabel)
        let contentStackView = UIStackView(arrangedSubviews: [teamAStackView, teamBStackView, startTimeLabel])
        contentStackView.axis = .horizontal
        contentStackView.alignment = .top
        contentStackView.distribution = .fill
        contentStackView.spacing = 16
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        teamAStackView.widthAnchor.constraint(
            equalTo: contentStackView.widthAnchor,
            multiplier: Layout.teamColumnWidthMultiplier
        ).isActive = true
        teamBStackView.widthAnchor.constraint(
            equalTo: contentStackView.widthAnchor,
            multiplier: Layout.teamColumnWidthMultiplier
        ).isActive = true

        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private func configureTeamLabel(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
    }

    private func configureOddsLabel(_ label: UILabel) {
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
    }

    private func makeTeamStackView(teamLabel: UILabel, oddsLabel: UILabel) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: [teamLabel, oddsLabel])
        stackView.axis = .vertical
        stackView.spacing = 6
        return stackView
    }
}

import UIKit

final class MatchTableViewCell: UITableViewCell {
    static let reuseIdentifier = "MatchTableViewCell"

    // MARK: - Properties

    private enum Layout {
        static let teamColumnWidthMultiplier = 0.3
    }

    private lazy var teamALabel = makeTeamLabel()
    private lazy var teamBLabel = makeTeamLabel()
    private lazy var startTimeLabel = makeStartTimeLabel()
    private lazy var teamAOddsLabel = makeOddsLabel()
    private lazy var teamBOddsLabel = makeOddsLabel()
    private lazy var teamAStackView = makeTeamStackView(teamLabel: teamALabel, oddsLabel: teamAOddsLabel)
    private lazy var teamBStackView = makeTeamStackView(teamLabel: teamBLabel, oddsLabel: teamBOddsLabel)
    private lazy var contentStackView = makeContentStackView()

    // MARK: - Lifecycle

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Methods

    func configure(with row: MatchRowViewModel) {
        teamALabel.text = row.teamA
        teamBLabel.text = row.teamB
        startTimeLabel.text = row.startTimeText
        teamAOddsLabel.text = row.teamAOddsText
        teamBOddsLabel.text = row.teamBOddsText
    }

    private func configureView() {
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }

    private func configureHierarchy() {
        contentView.addSubview(contentStackView)
    }

    private func configureConstraints() {
        teamAStackView.widthAnchor.constraint(
            equalTo: contentStackView.widthAnchor,
            multiplier: Layout.teamColumnWidthMultiplier
        ).isActive = true
        teamBStackView.widthAnchor.constraint(
            equalTo: contentStackView.widthAnchor,
            multiplier: Layout.teamColumnWidthMultiplier
        ).isActive = true

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    private func configureAppearance() {
        selectionStyle = .none
        accessoryType = .none
    }
}

// MARK: - Factory Methods

extension MatchTableViewCell {
    private func makeTeamLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeOddsLabel() -> UILabel {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        return label
    }

    private func makeStartTimeLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func makeTeamStackView(teamLabel: UILabel, oddsLabel: UILabel) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: [teamLabel, oddsLabel])
        stackView.axis = .vertical
        stackView.spacing = 6
        return stackView
    }

    private func makeContentStackView() -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: [teamAStackView, teamBStackView, startTimeLabel])
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }
}

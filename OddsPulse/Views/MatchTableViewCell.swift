import UIKit

final class MatchTableViewCell: UITableViewCell {
    static let reuseIdentifier = "MatchTableViewCell"

    private let titleLabel = UILabel()
    private let startTimeLabel = UILabel()
    private let oddsLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with row: MatchRowViewModel) {
        titleLabel.text = row.title
        startTimeLabel.text = row.startTimeText
        oddsLabel.text = row.oddsText
    }

    private func configureView() {
        selectionStyle = .none
        accessoryType = .none

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        startTimeLabel.font = .preferredFont(forTextStyle: .subheadline)
        startTimeLabel.textColor = .secondaryLabel
        startTimeLabel.adjustsFontForContentSizeCategory = true

        oddsLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        oddsLabel.textAlignment = .right
        oddsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStackView = UIStackView(arrangedSubviews: [titleLabel, startTimeLabel])
        textStackView.axis = .vertical
        textStackView.spacing = 4

        let contentStackView = UIStackView(arrangedSubviews: [textStackView, oddsLabel])
        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = 16
        contentStackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
}

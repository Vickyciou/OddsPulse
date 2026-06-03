import UIKit

@MainActor
final class MatchesViewController: UIViewController {

    private enum Layout {
        static let rowHeight: CGFloat = 72
    }

    // MARK: - Properties

    private let viewModel: MatchesViewModel
    private var rows: [MatchRowViewModel] = []

    private lazy var tableView = makeTableView()
    private lazy var activityIndicatorView = makeActivityIndicatorView()
    private lazy var messageLabel = makeMessageLabel()
    private lazy var connectionStatusLabel = makeConnectionStatusLabel()

    init(viewModel: MatchesViewModel? = nil) {
        self.viewModel = viewModel ?? MatchesViewModel()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        viewModel.stopObservingLiveOdds()
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        bindViewModel()
        viewModel.start()
    }

    // MARK: - Methods

    private func configureView() {
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }

    private func configureAppearance() {
        title = "OddsPulse"
        view.backgroundColor = .systemBackground
    }

    private func configureHierarchy() {
        view.addSubview(connectionStatusLabel)
        view.addSubview(tableView)
        view.addSubview(activityIndicatorView)
        view.addSubview(messageLabel)
    }

    private func configureConstraints() {
        NSLayoutConstraint.activate([
            connectionStatusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            connectionStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            connectionStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.topAnchor.constraint(equalTo: connectionStatusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            activityIndicatorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
        viewModel.onRowsUpdated = { [weak self] rows, updatedIndexes in
            self?.renderRowUpdates(rows: rows, updatedIndexes: updatedIndexes)
        }
        viewModel.onFeedStatusChange = { [weak self] feedStatus in
            self?.renderFeedStatus(feedStatus)
        }
    }

    private func render(_ state: MatchesViewState) {
        switch state {
        case .idle:
            rows = []
            activityIndicatorView.stopAnimating()
            messageLabel.isHidden = true
            tableView.isHidden = true
        case .loading:
            rows = []
            tableView.reloadData()
            tableView.isHidden = true
            messageLabel.isHidden = true
            activityIndicatorView.startAnimating()
        case let .loaded(rows):
            self.rows = rows
            tableView.reloadData()
            tableView.isHidden = rows.isEmpty
            messageLabel.text = "No matches available"
            messageLabel.isHidden = !rows.isEmpty
            activityIndicatorView.stopAnimating()
        case let .failed(message):
            rows = []
            tableView.reloadData()
            tableView.isHidden = true
            messageLabel.text = message
            messageLabel.isHidden = false
            activityIndicatorView.stopAnimating()
        }
    }

    private func renderRowUpdates(rows: [MatchRowViewModel], updatedIndexes: [Int]) {
        self.rows = rows

        let indexPaths = updatedIndexes.map { rowIndex in
            IndexPath(row: rowIndex, section: 0)
        }
        tableView.reloadRows(at: indexPaths, with: .none)
    }

    private func renderFeedStatus(_ feedStatus: LiveOddsFeedStatus) {
        switch feedStatus {
        case .idle:
            connectionStatusLabel.text = "Live odds idle"
            connectionStatusLabel.textColor = .secondaryLabel
        case .connecting:
            connectionStatusLabel.text = "Connecting odds..."
            connectionStatusLabel.textColor = .secondaryLabel
        case .live:
            connectionStatusLabel.text = "Live"
            connectionStatusLabel.textColor = .systemGreen
        case .reconnecting:
            connectionStatusLabel.text = "Reconnecting odds..."
            connectionStatusLabel.textColor = .systemOrange
        case let .unavailable(message):
            connectionStatusLabel.text = message
            connectionStatusLabel.textColor = .systemRed
        }
    }
}

// MARK: - Factory Methods

extension MatchesViewController {
    private func makeTableView() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.rowHeight = Layout.rowHeight
        tableView.register(
            MatchTableViewCell.self,
            forCellReuseIdentifier: MatchTableViewCell.reuseIdentifier
        )
        return tableView
    }

    private func makeActivityIndicatorView() -> UIActivityIndicatorView {
        let activityIndicatorView = UIActivityIndicatorView(style: .large)
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.hidesWhenStopped = true
        return activityIndicatorView
    }

    private func makeMessageLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }

    private func makeConnectionStatusLabel() -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        label.numberOfLines = 1
        label.text = "Live odds idle"
        return label
    }
}

// MARK: - UITableViewDataSource

extension MatchesViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: MatchTableViewCell.reuseIdentifier,
            for: indexPath
        ) as? MatchTableViewCell else {
            return UITableViewCell()
        }

        cell.configure(with: rows[indexPath.row])
        return cell
    }
}

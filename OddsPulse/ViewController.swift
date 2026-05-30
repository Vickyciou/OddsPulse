import UIKit

@MainActor
final class ViewController: UIViewController {
    private let viewModel: MatchesViewModel
    private var rows: [MatchRowViewModel] = []
    private var loadTask: Task<Void, Never>?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicatorView = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    init(viewModel: MatchesViewModel? = nil) {
        self.viewModel = viewModel ?? MatchesViewModel()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        bindViewModel()
        loadTask = Task { [viewModel] in
            await viewModel.loadInitialMatches()
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func configureView() {
        title = "OddsPulse"
        view.backgroundColor = .systemBackground

        configureTableView()
        configureActivityIndicatorView()
        configureMessageLabel()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(
            MatchTableViewCell.self,
            forCellReuseIdentifier: MatchTableViewCell.reuseIdentifier
        )
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureActivityIndicatorView() {
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.hidesWhenStopped = true
        view.addSubview(activityIndicatorView)

        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureMessageLabel() {
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
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
}

extension ViewController: UITableViewDataSource {
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

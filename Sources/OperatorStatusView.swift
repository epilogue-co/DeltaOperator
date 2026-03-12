//
//  OperatorStatusView.swift
//  DeltaOperator
//
//  Visualizes the current Operator cartridge slot state.
//

import OperatorKit
import UIKit

/// Visualizes the Operator cartridge slot state with an icon, label, and progress stroke.
public final class OperatorStatusView: UIView {
    private static let iconSize: CGFloat = 32
    private static let titleSpacing: CGFloat = 8
    private static let borderCornerRadius: CGFloat = 5
    private static let borderLineWidth: CGFloat = 1.5
    private static let borderDashPattern: [NSNumber] = [4, 4]
    private static let progressColor = UIColor(named: "Purple") ?? .systemPurple
    private static let progressAnimationDuration: CFTimeInterval = 0.25
    private static let progressAnimationKey = "progressAnimation"
    private static let strokeEndKeyPath = "strokeEnd"
    private static let connectedIcon = UIImage(systemName: "arrow.down.to.line.compact")
    private static let transferringIcon = UIImage(systemName: "arrow.down.circle")
    private static let insertCartridgeText = NSLocalizedString("Insert Cartridge", comment: "")
    private static let loadingFormat = NSLocalizedString("Loading… %d%%", comment: "")
    private var currentSlotState: OperatorSlotState = .connected
    private var lastBorderBounds: CGRect = .zero
    private var needsBorderRebuild = true

    private var imageWidthConstraint: NSLayoutConstraint!
    private var imageHeightConstraint: NSLayoutConstraint!
    private var viewWidthConstraint: NSLayoutConstraint!
    private var borderLayer: CAShapeLayer?
    private var progressStrokeLayer: CAShapeLayer?

    // MARK: - Subviews

    /// Controls the image container size to match the grid layout.
    var cellWidth: CGFloat = 0 {
        didSet {
            guard oldValue != self.cellWidth else { return }
            self.imageWidthConstraint.constant = self.cellWidth
            self.imageHeightConstraint.constant = self.cellWidth
            self.viewWidthConstraint.constant = self.cellWidth
            self.setNeedsLayout()
        }
    }

    /// Square container for the icon, drawn with a dotted border.
    private let imageContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        return container
    }()

    /// Centered icon indicating the current slot state.
    private let iconView: UIImageView = {
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }()

    /// Label below the icon showing status text or transfer progress.
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .gray
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    /// Creates the view programmatically.
    ///
    /// - Parameter frame: The initial frame rectangle for the view.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    /// Creates the view from a storyboard or xib.
    ///
    /// - Parameter coder: The archive to decode the view from.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    /// Adds subviews and configures the initial state.
    private func setup() {
        self.addSubview(self.imageContainer)
        self.imageContainer.addSubview(self.iconView)
        self.addSubview(self.titleLabel)
        self.createConstraints()
        self.activateConstraints()
        self.updateFont()
        self.configure(with: .connected)
    }

    /// Creates the stored constraint references.
    private func createConstraints() {
        self.imageWidthConstraint = self.imageContainer.widthAnchor.constraint(equalToConstant: self.cellWidth)
        self.imageHeightConstraint = self.imageContainer.heightAnchor.constraint(equalToConstant: self.cellWidth)
        self.imageHeightConstraint.priority = UILayoutPriority(999)
        self.viewWidthConstraint = self.widthAnchor.constraint(greaterThanOrEqualToConstant: self.cellWidth)
    }

    /// Activates all Auto Layout constraints for the view hierarchy.
    private func activateConstraints() {
        NSLayoutConstraint.activate([
            // Minimum width — prevents the view from shrinking when text changes.
            self.viewWidthConstraint,

            // Image container — top-aligned, centered horizontally.
            self.imageContainer.topAnchor.constraint(equalTo: self.topAnchor),
            self.imageContainer.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.imageWidthConstraint,
            self.imageHeightConstraint,

            // Icon — centered in container.
            self.iconView.centerXAnchor.constraint(equalTo: self.imageContainer.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.imageContainer.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            self.iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            // Title label — below image with 8pt spacing.
            self.titleLabel.topAnchor.constraint(equalTo: self.imageContainer.bottomAnchor, constant: Self.titleSpacing),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.titleLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    // MARK: - Layout

    /// Redraws border layers when the view's bounds change.
    public override func layoutSubviews() {
        super.layoutSubviews()
        self.updateBorderLayers()
    }

    /// Updates the title font when the horizontal size class changes.
    ///
    /// - Parameter previousTraitCollection: The previous trait collection before the change.
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if self.traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            self.updateFont()
        }
    }

    /// Selects the title font based on the current size class with monospaced digits.
    private func updateFont() {
        let style: UIFont.TextStyle = self.traitCollection.horizontalSizeClass == .regular ? .subheadline : .caption1
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        let styled = style == .subheadline ? descriptor.withSymbolicTraits(.traitBold)! : descriptor
        self.titleLabel.font = self.monospacedDigitsFont(from: styled)
    }

    /// Returns a font with monospaced digit spacing applied.
    ///
    /// - Parameter descriptor: The font descriptor to apply monospaced digits to.
    /// - Returns: A font with monospaced digit spacing.
    private func monospacedDigitsFont(from descriptor: UIFontDescriptor) -> UIFont {
        let mono = descriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        ])
        return UIFont(descriptor: mono, size: 0)
    }

    // MARK: - Border Drawing

    /// Rebuilds border and progress layers when bounds or state change.
    private func updateBorderLayers() {
        let bounds = self.imageContainer.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }

        guard self.needsBorderRebuild || bounds != self.lastBorderBounds else { return }
        self.lastBorderBounds = bounds
        self.needsBorderRebuild = false

        let path = UIBezierPath(roundedRect: bounds, cornerRadius: Self.borderCornerRadius)
        self.updateDottedBorder(path: path)
        self.updateProgressStroke(path: path)
    }

    /// Creates the dotted border layer if needed and updates its path.
    ///
    /// - Parameter path: The rounded rect path to use for the border.
    private func updateDottedBorder(path: UIBezierPath) {
        if self.borderLayer == nil {
            let border = CAShapeLayer()
            border.strokeColor = UIColor.secondaryLabel.cgColor
            border.fillColor = nil
            border.lineDashPattern = Self.borderDashPattern
            border.lineWidth = Self.borderLineWidth
            self.imageContainer.layer.addSublayer(border)
            self.borderLayer = border
        }
        self.borderLayer?.path = path.cgPath
    }

    /// Creates or removes the progress stroke layer based on the current state.
    ///
    /// - Parameter path: The rounded rect path to use for the stroke.
    private func updateProgressStroke(path: UIBezierPath) {
        if case .transferring(let progress) = self.currentSlotState {
            if self.progressStrokeLayer == nil {
                let stroke = CAShapeLayer()
                stroke.strokeColor = Self.progressColor.cgColor
                stroke.fillColor = nil
                stroke.lineWidth = Self.borderLineWidth
                stroke.lineCap = .round
                stroke.strokeEnd = 0
                self.imageContainer.layer.addSublayer(stroke)
                self.progressStrokeLayer = stroke
            }
            self.progressStrokeLayer?.path = path.cgPath
            self.animateProgress(to: progress)
        } else {
            self.progressStrokeLayer?.removeFromSuperlayer()
            self.progressStrokeLayer = nil
        }
    }

    /// Animates the progress stroke to the given fraction.
    ///
    /// - Parameter fraction: The progress value, clamped to 0...1.
    private func animateProgress(to fraction: Double) {
        guard let stroke = self.progressStrokeLayer else { return }

        let clamped = CGFloat(min(max(fraction, 0), 1))
        let animation = CABasicAnimation(keyPath: Self.strokeEndKeyPath)
        animation.fromValue = stroke.strokeEnd
        animation.toValue = clamped
        animation.duration = Self.progressAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        stroke.strokeEnd = clamped
        stroke.add(animation, forKey: Self.progressAnimationKey)
    }

    // MARK: - State Configuration

    /// Updates the icon, label, and border layers to reflect the given slot state.
    ///
    /// - Parameter slotState: The new slot state to display.
    func configure(with slotState: OperatorSlotState) {
        let previousState = self.currentSlotState
        self.currentSlotState = slotState

        switch slotState {
        case .connected:
            self.configureConnected()
        case .transferring(let progress):
            if !self.configureTransferring(progress, from: previousState) { return }
        case .disconnected, .imported:
            self.configureIdle()
        }

        self.needsBorderRebuild = true
        self.setNeedsLayout()
    }

    /// Sets the icon and label for the connected (waiting for cartridge) state.
    private func configureConnected() {
        self.iconView.image = Self.connectedIcon
        self.titleLabel.text = Self.insertCartridgeText
    }

    /// Updates the icon, label, and progress stroke for the transferring state.
    ///
    /// - Parameters:
    ///   - progress: The transfer progress fraction (0...1).
    ///   - previousState: The state before this update.
    /// - Returns: `false` if only the stroke was animated (no layout rebuild needed).
    private func configureTransferring(_ progress: Double, from previousState: OperatorSlotState) -> Bool {
        let percentText = String(format: Self.loadingFormat, Int(progress * 100))

        if case .transferring = previousState {
            if self.titleLabel.text != percentText { self.titleLabel.text = percentText }
            self.animateProgress(to: progress)
            return false
        }

        self.iconView.image = Self.transferringIcon
        self.titleLabel.text = percentText
        return true
    }

    /// Clears the icon and label for states where the view is not visible.
    private func configureIdle() {
        self.iconView.image = nil
        self.titleLabel.text = nil
    }
}

/// Wraps an OperatorStatusView for use in a UICollectionView.
public final class OperatorStatusCell: UICollectionViewCell {
    public static let reuseIdentifier = "OperatorStatusCell"
    let slotView = OperatorStatusView()

    var cellWidth: CGFloat {
        get { self.slotView.cellWidth }
        set { self.slotView.cellWidth = newValue }
    }

    // MARK: - Lifecycle

    /// Creates the cell programmatically.
    ///
    /// - Parameter frame: The initial frame rectangle for the cell.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }

    /// Creates the cell from a storyboard or xib.
    ///
    /// - Parameter coder: The archive to decode the cell from.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setup()
    }

    /// Forwards the slot state to the embedded status view.
    ///
    /// - Parameter slotState: The new slot state to display.
    func configure(with slotState: OperatorSlotState) {
        self.slotView.configure(with: slotState)
    }

    /// Adds the status view to the content view with edge-pinned constraints.
    private func setup() {
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        self.slotView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.slotView)
        NSLayoutConstraint.activate([
            self.slotView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.slotView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.slotView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.slotView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
        ])
    }
}

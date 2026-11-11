import UIKit
import YandexMobileAds

/// Карточка нативной рекламы в стиле приложения: белый фон, скруглённые углы, фиолетовая
/// кнопка действия. Все обязательные компоненты SDK 8 связаны со свойствами NativeAdView
/// (заголовок, домен, дисклеймер, метка «Реклама», кнопка обратной связи, кнопка действия,
/// медиа, иконка и цена для рекламы приложений): без этого объявление не покажется.
/// Элементы не перекрываются и не скрываются, высота определяется содержимым.
final class PitanieNativeAdView: NativeAdView {
  private static let accent = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0.635, green: 0.482, blue: 1.0, alpha: 1)
    : UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1) }
  private static let cardColor = UIColor { $0.userInterfaceStyle == .dark
    ? UIColor(red: 0.110, green: 0.110, blue: 0.149, alpha: 1)
    : UIColor.white }

  private let iconView = UIImageView()
  private let titleText = UILabel()
  private let domainText = UILabel()
  private let sponsoredText = UILabel()
  private let feedback = UIButton(type: .system)
  private let media = NativeMediaView()
  private let bodyText = UILabel()
  private let warningText = UILabel()
  private let priceText = UILabel()
  private let reviewsText = UILabel()
  private let faviconView = UIImageView()
  private let action = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    build()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    build()
  }

  private func label(_ style: UIFont.TextStyle, _ color: UIColor, lines: Int = 1, weight: UIFont.Weight? = nil) -> UILabel {
    let l = UILabel()
    var font = UIFont.preferredFont(forTextStyle: style)
    if let w = weight {
      font = UIFont.systemFont(ofSize: font.pointSize, weight: w)
    }
    l.font = font
    l.adjustsFontForContentSizeCategory = true
    l.textColor = color
    l.numberOfLines = lines
    return l
  }

  private func build() {
    backgroundColor = PitanieNativeAdView.cardColor
    layer.cornerRadius = 18
    layer.masksToBounds = true
    layer.borderWidth = 1
    layer.borderColor = UIColor.separator.cgColor

    // Стиль компонентов.
    iconView.layer.cornerRadius = 10
    iconView.clipsToBounds = true
    iconView.contentMode = .scaleAspectFill
    faviconView.contentMode = .scaleAspectFit

    let titleFont = UIFont.preferredFont(forTextStyle: .subheadline)
    titleText.font = UIFont.systemFont(ofSize: titleFont.pointSize, weight: .semibold)
    titleText.adjustsFontForContentSizeCategory = true
    titleText.textColor = .label
    titleText.numberOfLines = 2

    let caption = UIFont.preferredFont(forTextStyle: .caption1)
    for l in [domainText, sponsoredText, reviewsText, priceText] {
      l.font = caption
      l.adjustsFontForContentSizeCategory = true
      l.textColor = .secondaryLabel
    }
    priceText.textColor = .label
    priceText.font = UIFont.systemFont(ofSize: caption.pointSize, weight: .semibold)
    domainText.numberOfLines = 1
    sponsoredText.numberOfLines = 1

    bodyText.font = UIFont.preferredFont(forTextStyle: .footnote)
    bodyText.adjustsFontForContentSizeCategory = true
    bodyText.textColor = .secondaryLabel
    bodyText.numberOfLines = 3

    warningText.font = UIFont.preferredFont(forTextStyle: .caption2)
    warningText.adjustsFontForContentSizeCategory = true
    warningText.textColor = .tertiaryLabel
    warningText.numberOfLines = 0

    feedback.setImage(UIImage(systemName: "ellipsis"), for: .normal)
    feedback.tintColor = .secondaryLabel
    feedback.setContentHuggingPriority(.required, for: .horizontal)

    action.backgroundColor = PitanieNativeAdView.accent
    action.setTitleColor(.white, for: .normal)
    action.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
    action.titleLabel?.adjustsFontForContentSizeCategory = true
    action.layer.cornerRadius = 12
    action.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

    // Раскладка: шапка, медиа, текст, дисклеймер, нижняя строка.
    let nameRow = UIStackView(arrangedSubviews: [sponsoredText, domainText, UIView()])
    nameRow.axis = .horizontal
    nameRow.spacing = 6
    let nameStack = UIStackView(arrangedSubviews: [titleText, nameRow])
    nameStack.axis = .vertical
    nameStack.spacing = 2
    let header = UIStackView(arrangedSubviews: [iconView, nameStack, feedback])
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = 10

    let bottomLeft = UIStackView(arrangedSubviews: [faviconView, priceText, reviewsText])
    bottomLeft.axis = .horizontal
    bottomLeft.spacing = 6
    bottomLeft.alignment = .center
    let bottom = UIStackView(arrangedSubviews: [bottomLeft, UIView(), action])
    bottom.axis = .horizontal
    bottom.alignment = .center
    bottom.spacing = 8

    let root = UIStackView(arrangedSubviews: [header, media, bodyText, warningText, bottom])
    root.axis = .vertical
    root.spacing = 8
    root.translatesAutoresizingMaskIntoConstraints = false
    addSubview(root)

    iconView.translatesAutoresizingMaskIntoConstraints = false
    faviconView.translatesAutoresizingMaskIntoConstraints = false
    media.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
      iconView.widthAnchor.constraint(equalToConstant: 40),
      iconView.heightAnchor.constraint(equalToConstant: 40),
      faviconView.widthAnchor.constraint(equalToConstant: 16),
      faviconView.heightAnchor.constraint(equalToConstant: 16),
      // Для видео контейнер и медиа не меньше 300 × 160 (требование Яндекса).
      media.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
    ])
    let ratio = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 9.0 / 16.0)
    ratio.priority = .defaultHigh
    ratio.isActive = true

    // Привязка к свойствам NativeAdView.
    titleLabel = titleText
    domainLabel = domainText
    warningLabel = warningText
    sponsoredLabel = sponsoredText
    feedbackButton = feedback
    callToActionButton = action
    mediaView = media
    iconImageView = iconView
    priceLabel = priceText
    faviconImageView = faviconView
    reviewCountLabel = reviewsText
    bodyLabel = bodyText
  }

  /// Высота карточки при заданной ширине (по содержимому).
  func fittingHeight(width: CGFloat) -> CGFloat {
    let size = systemLayoutSizeFitting(
      CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel)
    return ceil(size.height)
  }
}

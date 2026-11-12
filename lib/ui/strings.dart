import '../core/errors.dart';
import '../models/store.dart';
import '../state/operations.dart';

/// All user-facing texts. Russian only for now.
///
/// Voice of the design system: buttons are actions with a capital letter,
/// labels are lowercase without punctuation, an error says how to fix it.
abstract final class S {
  static const appName = 'returner';
  static const cancel = 'отмена';
  static const retry = 'Повторить';

  // Setup
  static const setupLead =
      'Возвращает на iPhone приложения, которые исчезли из App Store, но всё ещё выдаются вашему Apple ID.';
  static const setupHow =
      'Скачивает оригинальные файлы Apple и ставит их по кабелю. Без джейлбрейка и переподписи.';
  static const setupStepsLabel = 'как это работает';
  static const setupStepLogin = 'Войдите в Apple ID';
  static const setupStepLoginMeta = 'пароль и код';
  static const setupStepDevice = 'Подключите iPhone кабелем';
  static const setupStepDeviceMeta = 'по usb';
  static const setupStepApp = 'Выберите приложение';
  static const setupStepAppMeta = 'каталог или id';
  static const setupContinue = 'Продолжить';
  static const setupChecking = 'проверяем компоненты и сессию Apple ID';
  static const setupFailed = 'не удалось подготовиться';

  // Login
  static const loginTitle = 'вход в apple id';
  static const loginEmail = 'apple id';
  static const loginEmailHint = 'name@icloud.com или телефон…';
  static const loginPassword = 'пароль';
  static const loginSubmit = 'Войти';
  static const loginPrivacy =
      'Данные Apple ID отправляются напрямую в Apple с этого компьютера. '
      'Мы их не храним и не пересылаем.';
  static const loginWorking = 'входим в Apple ID';
  static const loginWorkingHint =
      'Первый вход может занять несколько минут — не закрывайте окно.';
  static const loginCodeTitle = 'код подтверждения';
  static const loginCodeField = 'код из шести цифр';
  static const loginCodeHelper =
      'Код пришёл на ваше устройство Apple. Нужны все шесть цифр.';
  static const loginCodeSubmit = 'Подтвердить';
  static const loginNoCodeLabel = 'код не пришёл';
  static const loginNoCode =
      'Код показывается на iPhone, iPad или Mac с этим Apple ID — устройство '
      'должно быть в сети и разблокировано. Бывает, что Apple просит код, но '
      'не присылает его. Тогда войдите в account.apple.com в браузере, '
      'подтвердите вход на iPhone и введите сюда код, который он покажет. '
      'Если после этого появится ошибка, войдите в Returner ещё раз — '
      'обычно Apple уже пускает без кода.';
  static const loginResendCode = 'повторить вход без кода';
  static const loginFailed = 'не удалось войти';
  static String loginAppleLink(String host) => 'открыть $host';
  static const loginExpired =
      'Сессия истекла. Войдите в Apple ID заново — скачанные файлы на месте.';
  static const loginFillBoth = 'Нужны и Apple ID, и пароль.';

  // Components fetched before the first sign-in
  static const componentsLabel = 'подготовка ко входу';
  static const componentsChecking = 'проверяем компоненты для входа';
  static const componentsStarting = 'начинаем загрузку компонентов';
  static String componentsDownloading(ComponentStage stage) => switch (stage) {
    ComponentStage.runtime => 'скачиваем библиотеку эмулятора',
    ComponentStage.appleAssets => 'скачиваем компоненты Apple из образа macOS',
  };
  static const componentsWhy =
      'Один раз на этом компьютере: перед первым входом нужны компоненты '
      'с серверов Apple и GitHub — около 330 МБ загрузки, на диске они '
      'займут около 190 МБ.';
  static const componentsWait = 'Войти можно после загрузки компонентов.';
  static const componentsFailed = 'не удалось скачать компоненты';
  static const componentsFailedHint =
      'Повторите загрузку. Войти можно и сейчас — тогда компоненты '
      'будут скачиваться во время входа.';
  static const componentsRetry = 'Повторить загрузку';

  /// "64 из 184 МБ", or just "64 МБ" when the size is not known.
  static String componentsAmount(int bytes, int total) {
    String mb(int value) => '${(value / 1000000).round()}';
    return total > 0 ? '${mb(bytes)} из ${mb(total)} МБ' : '${mb(bytes)} МБ';
  }

  static String componentsRemaining(Duration? left) => switch (left) {
    null => 'оцениваем, сколько осталось',
    _ when left < const Duration(seconds: 5) => 'почти готово',
    _ when left < const Duration(minutes: 1) => 'осталось меньше минуты',
    _ => 'осталось ~${(left.inSeconds / 60).ceil()} мин',
  };

  // Navigation
  static const sectionCatalog = 'Каталог';
  static const sectionPurchases = 'Покупки';
  static const sectionSearch = 'Поиск';
  static const sectionFiles = 'Файлы';
  static const sectionSettings = 'Настройки';
  static const navDevice = 'устройство';
  static const navAccount = 'apple id';
  static const deviceNone = 'iPhone не подключён';
  static const deviceSeveral = 'Выберите iPhone';
  static const deviceDriverMissing = 'Нет драйвера Apple';
  static const accountNone = 'не подключён';
  static String deviceOs(String os) => os.isEmpty ? '' : 'iOS $os';

  // Notices at the top of a section
  static const driverTitle = 'нет драйвера apple';
  static const driverBody =
      'Windows не видит iPhone без драйвера Apple. Returner скачает с apple.com '
      'установщик iTunes (около 200 МБ), возьмёт из него только драйвер и службу '
      'Apple Mobile Device и установит их — сам iTunes ставиться не будет. '
      'Windows спросит разрешение — ответьте «Да». Устанавливая драйвер, вы '
      'принимаете лицензию Apple на это ПО.';
  static const driverInstall = 'Установить драйвер Apple';
  static String driverDownloading(double? fraction) => fraction == null
      ? 'скачиваем установщик с apple.com'
      : 'скачиваем установщик с apple.com — ${(fraction * 100).floor()} %';
  static const driverVerifying = 'проверяем подпись Apple';
  static const driverUnpacking = 'достаём драйвер из установщика';
  static const driverRunning = 'устанавливаем — в окне Windows ответьте «Да»';
  static const driverStarting = 'ждём, пока запустится служба Apple';
  static const driverCancelledTitle = 'установка отменена';
  static const driverCancelledBody =
      'Windows не получила разрешение. Нажмите «Повторить» и в окне Windows '
      'ответьте «Да». Если Windows просит пароль — нужен пароль администратора '
      'этого компьютера.';
  static const driverDownloadTitle = 'не удалось скачать установщик';
  static const driverDownloadBody =
      'Проверьте подключение к интернету и попробуйте ещё раз. Установщик '
      'берётся только с apple.com.';
  static const driverUntrustedTitle = 'файл не прошёл проверку';
  static const driverUntrustedBody =
      'Скачанный установщик не подписан Apple, поэтому Returner его не '
      'запускает. Попробуйте позже или поставьте iTunes с сайта Apple вручную.';
  static const driverUnpackTitle = 'не удалось распаковать установщик';
  static const driverUnpackBody =
      'Возможно, не хватает места на диске или Apple изменила установщик. '
      'Освободите место и повторите или поставьте iTunes с сайта Apple вручную.';
  static const driverFailedTitle = 'драйвер не установился';
  static const driverFailedBody =
      'Установщик Apple завершился с ошибкой. Перезагрузите компьютер и '
      'повторите или поставьте iTunes с сайта Apple вручную, затем '
      'переподключите iPhone.';
  static const driverItunes = 'iTunes на apple.com';
  static const severalTitle = 'подключено несколько iphone';
  static const severalBody =
      'Выберите, на какой ставить. Пока не выбрано — приложение можно только скачать.';

  // Catalog
  static const catalogLabel = 'каталог';
  static const catalogFilter = 'найти в каталоге';
  static const catalogFilterHint = 'название или app store id…';
  static const catalogOpenSearch = 'Искать в App Store';
  static String catalogEmpty(String query) =>
      'В каталоге нет «$query». Попробуйте короче или найдите приложение в App Store по названию, ID или ссылке.';

  // Purchases
  static const purchasesLabel = 'покупки apple id';
  static const purchasesFilter = 'найти в покупках';
  static const purchasesFilterHint = 'название, bundle id или app store id…';
  static const purchasesRefresh = 'обновить';
  static const purchasesMore = 'ещё';
  static const purchasesNeverLabel = 'ещё не загружены';
  static const purchasesNever =
      'Здесь будут все приложения, которые этот Apple ID когда-либо получал, '
      'в том числе исчезнувшие из App Store. Список загружается один раз и '
      'хранится на этом компьютере.';
  static const purchasesLoad = 'Загрузить покупки';
  static const purchasesEmptyLabel = 'покупок нет';
  static const purchasesEmpty =
      'Apple не вернула ни одного приложения для iPhone в истории этого Apple ID.';
  static const purchasesRefreshFailed = 'Не удалось обновить покупки';
  static String purchasesLoading(int loaded, int total) =>
      total == 0 ? 'загружаем покупки' : 'загружаем покупки: $loaded из $total';
  static String purchasesSynced(DateTime date) =>
      'обновлено ${shortDateTime(date)}';

  static String purchasesFilterEmpty(String query) =>
      'В покупках нет «$query». Если приложение купили недавно, обновите список.';
  static const _months = [
    'январь', 'февраль', 'март', 'апрель', 'май', 'июнь', //
    'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь',
  ];

  /// List-style date: «июль 2026».
  static String monthYear(DateTime date) =>
      '${_months[date.month - 1]} ${date.year}';

  // Search
  static const searchLabel = 'поиск';
  static const searchField = 'название, app store id или ссылка';
  static const searchHint = 'сбербанк, 6749261529 или ссылка apps.apple.com…';
  static const searchHelper =
      'По названию находит только то, что ещё есть в App Store. '
      'Исчезнувшее приложение ищите по ID или ссылке.';
  static const searchSubmit = 'Найти';
  static const searchWorking = 'ищем в App Store';
  static const searchById = 'по app store id';
  static const searchResults = 'в app store';
  static const searchEmptyLabel = 'ничего не нашлось';
  static String searchEmpty(String query) =>
      'В App Store нет приложений по запросу «$query». '
      'Если приложение исчезло из магазина, введите его App Store ID или ссылку.';

  // Files
  static const filesLabel = 'скачанные приложения';
  static const filesEmptyLabel = 'пока пусто';
  static const filesEmpty =
      'Здесь появятся скачанные приложения. Их можно ставить повторно без '
      'интернета и без входа в Apple ID.';
  static const filesOpenCatalog = 'Открыть каталог';
  static String megabytes(int bytes) =>
      '${(bytes / (1000 * 1000)).toStringAsFixed(1)} МБ';

  // Install panel
  static const panelLabel = 'установка';
  static const panelEmptyLabel = 'ничего не выбрано';
  static const panelEmpty =
      'Выберите приложение в списке — здесь появятся действия.';
  static const actionInstall = 'Установить на iPhone';
  static const actionDownload = 'Скачать файл';
  static const actionExport = 'Сохранить файл';
  static const actionRemove = 'Удалить';
  static const actionGetLicense = 'Получить бесплатно и продолжить';
  static const needDevice = 'Установка недоступна: iPhone не подключён.';
  static const kvId = 'app store id';
  static const kvStore = 'опубликовано как';
  static const kvBundle = 'bundle id';
  static const kvVersion = 'версия';
  static const kvSize = 'размер';
  static const kvMinOs = 'нужна ios';
  static const kvSha = 'sha-256';
  static const exported = 'Файл сохранён';
  static const removeTitle = 'Удалить файл приложения?';
  static const removeBody =
      'Файл исчезнет из «Файлов». С iPhone приложение не удалится, а скачать его '
      'снова можно, пока Apple его выдаёт.';
  static const removed = 'Файл удалён';
  static const activityLabel = 'сейчас';
  static const actionPickVersion = 'Выбрать версию';
  static const actionOlderVersion = 'Выбрать версию постарше';
  static const kvPinned = 'выбрана';
  static String pinnedVersion(String id, String? display) =>
      display == null ? 'сборка $id' : '$display · сборка $id';
  static const copyReport = 'скопировать отчёт';
  static const reportCopied = 'Отчёт скопирован — личных данных в нём нет';

  // Version picker
  static const versionsTitle = 'Какую версию поставить?';
  static const versionsLoading =
      'получаем список версий у Apple — это может занять до минуты';
  static const versionsFailed = 'не удалось получить версии';
  static String versionsHint(int count) =>
      'Сборок: $count, сверху новые. Apple называет их номерами; '
      'настоящую версию можно узнать по одной — каждый запрос идёт до минуты.';
  static const versionsBuild = 'сборка';
  static String seconds(int value) => '$value с';
  static const versionsNewest = 'последняя';
  static const versionsResolve = 'узнать версию';
  static const versionsRetry = 'ещё раз';
  static const versionsMore = 'показать ещё';
  static const versionsRefresh = 'обновить';
  static const versionsRefreshFailed = 'не удалось обновить список';
  static const versionsLookupFailed = 'не удалось узнать версию';
  static const versionsLookupFailedShort = '! не удалось узнать версию';
  static String versionsFetched(DateTime date) =>
      'список от ${shortDateTime(date)}';
  static const versionsLatest = 'Последняя версия';
  static String shortDate(DateTime date) =>
      '${'${date.day}'.padLeft(2, '0')}.${'${date.month}'.padLeft(2, '0')}.${date.year}';

  /// Local date and time: 08.11.2026, 19:30.
  static String shortDateTime(DateTime date) {
    final local = date.toLocal();
    return '${shortDate(local)}, '
        '${'${local.hour}'.padLeft(2, '0')}:${'${local.minute}'.padLeft(2, '0')}';
  }

  static const activityShow = 'показать';

  // Operation results (notice titles are lowercase)
  static const doneDownloaded = 'скачано';
  static const doneDownloadedBody =
      'Файл лежит в «Файлах». Его можно поставить на iPhone в любой момент.';
  static const doneInstalled = 'установлено';
  static const doneVersionUnknown = 'установлено, версия не подтверждена';
  static const doneVersionUnknownBody =
      'iPhone показывает приложение, но с другой версией. Проверьте на телефоне, обновилось ли оно.';
  static const doneUnverified = 'установщик сообщил об успехе';
  static const doneUnverifiedBody =
      'iPhone не показал приложение в списке. Проверьте телефон: возможно, мешает «Экранное время».';
  static const resultUnknown = 'результат неизвестен';
  static const resultUnknownBody =
      'Связь с iPhone пропала во время установки. Посмотрите, появилось ли приложение, и только потом повторяйте.';
  static const cancelled = 'отменено';
  static const cancelledBody = 'Задача остановлена, недокачанный файл удалён.';
  static const failed = 'не получилось';
  static const noLicense = 'нет в покупках';
  static const noLicenseBody =
      'Этот Apple ID ни разу не скачивал это приложение. Если оно бесплатное и Apple его ещё выдаёт, '
      'его можно получить сейчас — так же, как кнопкой «Загрузить» в App Store. Оно появится в покупках аккаунта.';
  static String installedBody(String name, String? version) => version == null
      ? '«$name» на iPhone.'
      : '«$name» $version на iPhone — версия подтверждена.';

  // Settings
  static const settingsAccount = 'аккаунт apple id';
  static const settingsLogout = 'Выйти';
  static const settingsLogoutNote =
      'Выход удаляет сессию с этого компьютера. Скачанные приложения остаются в «Файлах».';
  static const settingsTheme = 'тема';
  static const themeNight = 'Ночь';
  static const themePaper = 'День';
  static const settingsCountry = 'страна магазина';
  static const settingsCountryNote =
      'Откуда брать названия и иконки приложений. На скачивание не влияет: оно идёт через регион вашего Apple ID.';
  static const settingsLog = 'журнал';
  static const settingsLogNote =
      'В отчёте — версия, последние операции и конец журнала. Почта, пароли, коды и номера устройств в него не попадают.';
  static const copyReportButton = 'Скопировать отчёт';
  static const openLogFolder = 'Открыть папку журнала';
  static const settingsAbout = 'о программе';
  static const aboutLicenses = 'Лицензии';
  static const aboutLicensesTitle = 'Лицензии компонентов';
  static const aboutPatched =
      'ipatool собран из исходников версии 2.8.0 с исправлениями, вышедшими после неё, и с нашим изменением: пароль, код и ключ хранилища '
      'передаются через stdin, а не аргументами, и сессия хранится в отдельной папке приложения. '
      'Изменение лежит рядом с исходниками в tools/patches.';
  static const aboutClose = 'закрыть';
  static const aboutSource = 'исходники';
  static const updatesLabel = 'обновления';
  static const updatesOnStart = 'Проверять при запуске';
  static const updatesOnStartNote =
      'Returner спрашивает у GitHub, вышла ли новая версия. В запросе только '
      'номер версии Returner, без Apple ID и данных устройства. Ничего не '
      'скачивается само: новую версию вы ставите сами со страницы релиза.';
  static const updatesCheck = 'проверить';
  static const updatesChecking = 'проверяем';
  static const updatesUpToDate = 'установлена последняя версия';
  static const updatesFailed =
      'не удалось проверить: GitHub не ответил. Проверьте интернет и повторите.';
  static String updatesAvailable(String version) => 'доступна версия $version';
  static String updatesAvailableBody(String current) =>
      'Сейчас установлена $current. Скачайте установщик со страницы релиза и '
      'запустите его.';
  static const updatesOpen = 'Открыть страницу релиза';
  static String updatesNav(String version) => 'версия $version';
  static const aboutVersion = 'версия';
  static const aboutEngine = 'компоненты';
  static const aboutData = 'данные';
  static const aboutDataValue = 'только на этом компьютере';

  /// Short status of a running operation, lowercase.
  static String runningStatus(Operation operation) => switch (operation.stage) {
    OperationStage.queued => 'в очереди',
    OperationStage.checkingLicense => 'проверяем лицензию',
    OperationStage.acquiringLicense => 'получаем лицензию',
    OperationStage.downloading => 'скачиваем — ${megabytes(operation.bytes)}',
    OperationStage.validating => 'проверяем файл',
    OperationStage.installing =>
      operation.installPercent == null ? 'передаём на iPhone' : 'устанавливаем',
    OperationStage.verifying => 'сверяем с iPhone',
    _ => '',
  };

  /// What went wrong and what to do about it.
  static String errorText(AppError error) => switch (error) {
    AuthInvalidCredentials() => 'Apple не приняла Apple ID или пароль. Проверьте раскладку и попробуйте ещё раз.',
    AuthNeeds2FA() => loginCodeHelper,
    AuthInvalidCode() =>
      'Код не подошёл. Отмените вход, начните заново и введите новый код.',
    AuthRateLimited() => 'Apple временно ограничила попытки входа. Подождите несколько минут и попробуйте снова.',
    AuthSessionExpired() => 'Сессия истекла. Войдите в Apple ID заново.',
    StorageLocked() => 'Не удалось открыть сохранённую сессию Apple ID. Войдите заново — прежние данные сохранены в резервной папке.',
    AppleUnreachable() => 'Нет связи с серверами Apple. Проверьте интернет; если включён VPN — выключите его, если выключен — включите.',
    AppleSignInMessage(:final message) => _withReason(
      'Apple не пустила во вход',
      message,
    ),
    AppleLoginRejected() => 'Apple сейчас не принимает вход: серверы отвечают пустым ответом, и дело не в пароле. Так бывает, когда Apple меняет порядок входа, — нужна новая версия Returner. Попробуйте позже или с другой сети.',
    AccountNotReady() => 'Этот Apple ID ещё не готов к загрузкам. Войдите под ним в App Store на iPhone и примите условия.',
    LicenseRequired() => noLicenseBody,
    LicenseRefused(:final appleMessage) => _withReason(
      'Apple не выдала лицензию: приложение платное или больше не распространяется. '
      'Вернуть можно только то, что этот Apple ID уже скачивал',
      appleMessage,
    ),
    AssetUnavailable(:final appleMessage) => _withReason(
      'Apple не выдаёт это приложение вашему аккаунту. Проверьте ID или попробуйте другую публикацию',
      appleMessage,
    ),
    RedownloadRefused() => 'Apple не отдала файл: приложения уже нет в App Store, а запрос на повторную загрузку она отклонила без объяснения. Это не окончательный отказ — повторите позже; если не поможет, выберите другую публикацию.',
    VersionUnavailable() =>
      'Эта версия недоступна. Выберите другую версию приложения.',
    NetworkInterrupted() => 'Соединение обрывалось даже после повторов. Проверьте интернет и нажмите «Повторить».',
    PackageInvalid() => 'Apple прислала повреждённый файл. Нажмите «Повторить», чтобы скачать его заново.',
    DiskFull() =>
      'На диске компьютера не хватило места. Освободите место и повторите.',
    DeviceNotFound() => 'iPhone отключился. Подключите его кабелем, разблокируйте и повторите — файл уже скачан.',
    DeviceNotTrusted() => 'iPhone не доверяет этому компьютеру. Разблокируйте его, нажмите «Доверять» и введите код-пароль.',
    DeviceLocked() => 'iPhone заблокирован. Разблокируйте его и держите разблокированным до конца установки.',
    DriverMissing() => driverBody,
    InsufficientSpace() =>
      'На iPhone не хватает места. Освободите память на телефоне и повторите.',
    IncompatibleOS() => 'Эта версия приложения требует более новую iOS, чем на вашем iPhone. Выберите версию постарше.',
    InstallConflict() => 'На iPhone уже есть это приложение из другого источника или идёт его загрузка. Удалите его с телефона и повторите.',
    InstallRejected() => 'iPhone отклонил установку. Проверьте «Экранное время» → «Установка приложений» и повторите.',
    InstallResultUnknown() => resultUnknownBody,
    ComponentMissing(:final component) =>
      'Не найден компонент «$component». Переустановите приложение.',
    Cancelled() => cancelledBody,
    Unclassified() => 'Причину определить не удалось. Повторите; если ошибка останется, пришлите отчёт.',
  };

  static String _withReason(String text, String? reason) =>
      reason == null ? '$text.' : '$text. Ответ Apple: $reason';
}

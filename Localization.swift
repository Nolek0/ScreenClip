import Foundation

/// In-app language choice ("system" follows macOS). English strings are the keys.
enum Lang {
    static let all: [(code: String, name: String)] = [
        ("en", "English"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"), ("it", "Italiano"),
        ("pt", "Português"), ("zh", "简体中文"), ("ja", "日本語"), ("ko", "한국어"), ("ru", "Русский"),
    ]
    /// Column order of the translation table below.
    static let order = ["fr", "es", "de", "it", "pt", "zh", "ja", "ko", "ru"]

    static var current: String {
        let chosen = UserDefaults.standard.string(forKey: "language") ?? "system"
        if chosen != "system" { return chosen }
        for pref in Locale.preferredLanguages {
            let code = String(pref.prefix(2))
            if all.contains(where: { $0.code == code }) { return code }
        }
        return "en"
    }

    static var locale: Locale {
        Locale(identifier: ["pt": "pt_BR", "zh": "zh_Hans"][current] ?? current)
    }
}

func L(_ key: String) -> String {
    let code = Lang.current
    guard code != "en", let row = translations[key], let i = Lang.order.firstIndex(of: code), i < row.count
    else { return key }
    return row[i]
}

func Lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

// English key: [fr, es, de, it, pt (BR), zh (Hans), ja, ko, ru]
private let translations: [String: [String]] = [
    // Menu bar
    "Folder: %@": ["Dossier : %@", "Carpeta: %@", "Ordner: %@", "Cartella: %@", "Pasta: %@", "文件夹：%@", "フォルダ：%@", "폴더: %@", "Папка: %@"],
    "History": ["Historique", "Historial", "Verlauf", "Cronologia", "Histórico", "历史记录", "履歴", "기록", "История"],
    "Copy Automatically": ["Copier automatiquement", "Copiar automáticamente", "Automatisch kopieren", "Copia automaticamente", "Copiar automaticamente", "自动复制", "自動でコピー", "자동으로 복사", "Копировать автоматически"],
    "Settings…": ["Réglages…", "Ajustes…", "Einstellungen…", "Impostazioni…", "Ajustes…", "设置…", "設定…", "설정…", "Настройки…"],
    "Check for Updates…": ["Rechercher des mises à jour…", "Buscar actualizaciones…", "Nach Updates suchen…", "Controlla aggiornamenti…", "Verificar atualizações…", "检查更新…", "アップデートを確認…", "업데이트 확인…", "Проверить обновления…"],
    "Update %@ Available": ["Mise à jour %@ disponible", "Actualización %@ disponible", "Update %@ verfügbar", "Aggiornamento %@ disponibile", "Atualização %@ disponível", "有可用更新 %@", "アップデート %@ があります", "%@ 업데이트 가능", "Доступно обновление %@"],
    "Quit ScreenClip": ["Quitter ScreenClip", "Salir de ScreenClip", "ScreenClip beenden", "Esci da ScreenClip", "Sair do ScreenClip", "退出 ScreenClip", "ScreenClip を終了", "ScreenClip 종료", "Завершить ScreenClip"],
    "No screenshots yet": ["Aucune capture pour l'instant", "Aún no hay capturas", "Noch keine Bildschirmfotos", "Ancora nessuno screenshot", "Nenhuma captura ainda", "还没有截图", "スクリーンショットはまだありません", "아직 스크린샷이 없습니다", "Снимков пока нет"],
    "Clear History": ["Vider l'historique", "Borrar historial", "Verlauf löschen", "Cancella cronologia", "Limpar histórico", "清除历史记录", "履歴を消去", "기록 지우기", "Очистить историю"],
    "Delete History Permanently": ["Supprimer définitivement", "Eliminar definitivamente", "Endgültig löschen", "Elimina definitivamente", "Excluir definitivamente", "永久删除历史记录", "履歴を完全に削除", "기록 영구 삭제", "Удалить навсегда"],
    "Skip Trash (Delete Permanently)": ["Sans passer par la Corbeille", "Sin pasar por la Papelera", "Papierkorb überspringen", "Salta il Cestino", "Ignorar a Lixeira", "不经过废纸篓（永久删除）", "ゴミ箱を使わない（完全に削除）", "휴지통 건너뛰기(영구 삭제)", "Без Корзины (удалить навсегда)"],
    "Click a screenshot to copy it": ["Clique sur une capture pour la copier", "Haz clic en una captura para copiarla", "Klicke auf ein Bildschirmfoto, um es zu kopieren", "Fai clic su uno screenshot per copiarlo", "Clique em uma captura para copiá-la", "点按截图即可复制", "クリックしてコピー", "스크린샷을 클릭하여 복사", "Нажмите на снимок, чтобы скопировать"],
    "Click a screenshot to open it": ["Clique sur une capture pour l'ouvrir", "Haz clic en una captura para abrirla", "Klicke auf ein Bildschirmfoto, um es zu öffnen", "Fai clic su uno screenshot per aprirlo", "Clique em uma captura para abri-la", "点按截图即可打开", "クリックして開く", "스크린샷을 클릭하여 열기", "Нажмите на снимок, чтобы открыть"],
    "Open History Folder": ["Ouvrir le dossier de l'historique", "Abrir carpeta del historial", "Verlaufsordner öffnen", "Apri cartella cronologia", "Abrir pasta do histórico", "打开历史记录文件夹", "履歴フォルダを開く", "기록 폴더 열기", "Открыть папку истории"],
    "Permanently delete %d screenshots?": ["Supprimer définitivement %d captures ?", "¿Eliminar definitivamente %d capturas?", "%d Bildschirmfotos endgültig löschen?", "Eliminare definitivamente %d screenshot?", "Excluir definitivamente %d capturas?", "要永久删除 %d 张截图吗？", "%d 件のスクリーンショットを完全に削除しますか？", "스크린샷 %d개를 영구 삭제하시겠습니까?", "Удалить навсегда снимков: %d?"],
    "They won't go to the Trash. This can't be undone.": ["Elles ne passeront pas par la Corbeille. Action irréversible.", "No irán a la Papelera. No se puede deshacer.", "Sie werden nicht in den Papierkorb gelegt. Dies kann nicht widerrufen werden.", "Non finiranno nel Cestino. L'operazione è irreversibile.", "Elas não irão para a Lixeira. Esta ação não pode ser desfeita.", "它们不会被移到废纸篓。此操作无法撤销。", "ゴミ箱には入りません。この操作は取り消せません。", "휴지통으로 이동하지 않습니다. 이 작업은 되돌릴 수 없습니다.", "Они не попадут в Корзину. Это действие нельзя отменить."],
    "Delete Permanently": ["Supprimer définitivement", "Eliminar definitivamente", "Endgültig löschen", "Elimina definitivamente", "Excluir definitivamente", "永久删除", "完全に削除", "영구 삭제", "Удалить навсегда"],
    "Cancel": ["Annuler", "Cancelar", "Abbrechen", "Annulla", "Cancelar", "取消", "キャンセル", "취소", "Отмена"],
    "Couldn't change Launch at Login": ["Impossible de modifier l'ouverture au démarrage", "No se pudo cambiar el inicio de sesión", "Anmeldeobjekt konnte nicht geändert werden", "Impossibile modificare l'apertura al login", "Não foi possível alterar a abertura no login", "无法更改登录时打开", "ログイン時の起動を変更できません", "로그인 시 열기를 변경할 수 없습니다", "Не удалось изменить автозапуск"],
    "Move ScreenClip.app to your Applications folder and try again.": ["Place ScreenClip.app dans le dossier Applications puis réessaie.", "Mueve ScreenClip.app a la carpeta Aplicaciones e inténtalo de nuevo.", "Bewege ScreenClip.app in den Ordner Programme und versuche es erneut.", "Sposta ScreenClip.app nella cartella Applicazioni e riprova.", "Mova o ScreenClip.app para a pasta Aplicativos e tente novamente.", "请将 ScreenClip.app 移到“应用程序”文件夹后重试。", "ScreenClip.app をアプリケーションフォルダに移動してもう一度お試しください。", "ScreenClip.app을 응용 프로그램 폴더로 옮긴 후 다시 시도하세요.", "Переместите ScreenClip.app в папку «Программы» и повторите попытку."],

    "Copy": ["Copier", "Copiar", "Kopieren", "Copia", "Copiar", "拷贝", "コピー", "복사", "Копировать"],
    "Open": ["Ouvrir", "Abrir", "Öffnen", "Apri", "Abrir", "打开", "開く", "열기", "Открыть"],
    "Right-click for more options": ["Clic droit pour plus d'options", "Clic derecho para más opciones", "Rechtsklick für weitere Optionen", "Clic destro per altre opzioni", "Clique com o botão direito para mais opções", "右键点按以获取更多选项", "右クリックでその他のオプション", "더 많은 옵션은 오른쪽 클릭", "Правый клик — другие действия"],
    "Also delete the original screenshots": ["Supprimer aussi les captures d'origine", "Eliminar también las capturas originales", "Auch die Original-Bildschirmfotos löschen", "Elimina anche gli screenshot originali", "Excluir também as capturas originais", "同时删除原始截图", "元のスクリーンショットも削除", "원본 스크린샷도 삭제", "Удалять и исходные снимки"],
    "Clearing or deleting from the history also removes the screenshot files from your Desktop.": ["Vider ou supprimer dans l'historique supprime aussi les fichiers de capture du Bureau.", "Al borrar o eliminar del historial también se eliminan los archivos de captura del Escritorio.", "Beim Löschen aus dem Verlauf werden auch die Bildschirmfoto-Dateien vom Schreibtisch entfernt.", "Cancellando o eliminando dalla cronologia vengono rimossi anche i file degli screenshot dalla Scrivania.", "Limpar ou excluir do histórico também remove os arquivos de captura da Mesa.", "清除或删除历史记录时，也会移除桌面上的截图文件。", "履歴から消去・削除すると、デスクトップのスクリーンショットファイルも削除されます。", "기록에서 지우거나 삭제하면 데스크탑의 스크린샷 파일도 제거됩니다.", "При очистке или удалении из истории файлы снимков также удаляются с Рабочего стола."],
    "Screen Recording": ["Enregistrement d'écran", "Grabación de pantalla", "Bildschirmaufnahme", "Registrazione schermo", "Gravação de tela", "屏幕录制", "画面収録", "화면 기록", "Запись экрана"],
    "Record the screen with a shortcut": ["Enregistrer l'écran avec un raccourci", "Grabar la pantalla con un atajo", "Bildschirm per Kurzbefehl aufnehmen", "Registra lo schermo con una scorciatoia", "Gravar a tela com um atalho", "使用快捷键录制屏幕", "ショートカットで画面を収録", "단축키로 화면 기록", "Запись экрана по сочетанию клавиш"],
    "Press %@ to start recording the screen, and again to stop. The video goes to your clipboard and history.": ["Appuie sur %@ pour lancer l'enregistrement de l'écran, et encore pour l'arrêter. La vidéo va dans le presse-papier et l'historique.", "Pulsa %@ para empezar a grabar la pantalla y otra vez para parar. El vídeo va al portapapeles y al historial.", "Drücke %@, um die Aufnahme zu starten, und erneut, um sie zu beenden. Das Video landet in der Zwischenablage und im Verlauf.", "Premi %@ per avviare la registrazione e di nuovo per fermarla. Il video va negli appunti e nella cronologia.", "Pressione %@ para começar a gravar a tela e de novo para parar. O vídeo vai para a área de transferência e o histórico.", "按 %@ 开始录制屏幕，再按一次停止。视频会放入剪贴板和历史记录。", "%@ を押すと画面収録を開始し、もう一度押すと停止します。ビデオはクリップボードと履歴に入ります。", "%@ 키를 누르면 화면 기록이 시작되고, 다시 누르면 멈춥니다. 동영상은 클립보드와 기록에 저장됩니다.", "Нажмите %@, чтобы начать запись экрана, и ещё раз, чтобы остановить. Видео попадёт в буфер обмена и историю."],
    "Shortcut": ["Raccourci", "Atajo", "Kurzbefehl", "Scorciatoia", "Atalho", "快捷键", "ショートカット", "단축키", "Сочетание клавиш"],
    "Start Recording": ["Démarrer l'enregistrement", "Empezar a grabar", "Aufnahme starten", "Avvia registrazione", "Iniciar gravação", "开始录制", "収録を開始", "기록 시작", "Начать запись"],
    "Stop Recording": ["Arrêter l'enregistrement", "Detener grabación", "Aufnahme beenden", "Interrompi registrazione", "Parar gravação", "停止录制", "収録を停止", "기록 중단", "Остановить запись"],
    "Screen recording permission needed": ["Autorisation d'enregistrement d'écran requise", "Se necesita permiso de grabación de pantalla", "Berechtigung für Bildschirmaufnahme erforderlich", "Serve il permesso di registrazione schermo", "Permissão de gravação de tela necessária", "需要屏幕录制权限", "画面収録の許可が必要です", "화면 기록 권한이 필요합니다", "Нужно разрешение на запись экрана"],
    "Allow ScreenClip in System Settings › Privacy & Security › Screen & System Audio Recording, then try again.": ["Autorise ScreenClip dans Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran et de l'audio du système, puis réessaie.", "Permite ScreenClip en Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema, y vuelve a intentarlo.", "Erlaube ScreenClip unter Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme und versuche es erneut.", "Consenti ScreenClip in Impostazioni di Sistema › Privacy e sicurezza › Registrazione schermo e audio di sistema, poi riprova.", "Permita o ScreenClip em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e Áudio do Sistema e tente novamente.", "请在“系统设置”›“隐私与安全性”›“录屏与系统录音”中允许 ScreenClip，然后重试。", "システム設定 › プライバシーとセキュリティ › 画面収録とシステムオーディオ録音 で ScreenClip を許可してから、もう一度お試しください。", "시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 기록에서 ScreenClip을 허용한 후 다시 시도하세요.", "Разрешите ScreenClip в Системных настройках › Конфиденциальность и безопасность › Запись экрана и системного звука и повторите попытку."],
    "Open System Settings": ["Ouvrir Réglages Système", "Abrir Ajustes del Sistema", "Systemeinstellungen öffnen", "Apri Impostazioni di Sistema", "Abrir Ajustes do Sistema", "打开系统设置", "システム設定を開く", "시스템 설정 열기", "Открыть Системные настройки"],
    "Share": ["Partager", "Compartir", "Teilen", "Condividi", "Compartilhar", "共享", "共有", "공유", "Поделиться"],
    "Delete": ["Supprimer", "Eliminar", "Löschen", "Elimina", "Excluir", "删除", "削除", "삭제", "Удалить"],

    // Settings window
    "ScreenClip Settings": ["Réglages de ScreenClip", "Ajustes de ScreenClip", "ScreenClip-Einstellungen", "Impostazioni di ScreenClip", "Ajustes do ScreenClip", "ScreenClip 设置", "ScreenClip 設定", "ScreenClip 설정", "Настройки ScreenClip"],
    "General": ["Général", "General", "Allgemein", "Generali", "Geral", "通用", "一般", "일반", "Основные"],
    "Updates": ["Mises à jour", "Actualizaciones", "Updates", "Aggiornamenti", "Atualizações", "更新", "アップデート", "업데이트", "Обновления"],
    "About": ["À propos", "Acerca de", "Über", "Info", "Sobre", "关于", "情報", "정보", "О программе"],
    "Language": ["Langue", "Idioma", "Sprache", "Lingua", "Idioma", "语言", "言語", "언어", "Язык"],
    "System Default": ["Langue du système", "Idioma del sistema", "Systemsprache", "Lingua di sistema", "Idioma do sistema", "跟随系统", "システムに従う", "시스템 기본값", "Как в системе"],
    "Screenshots": ["Captures d'écran", "Capturas de pantalla", "Bildschirmfotos", "Screenshot", "Capturas de tela", "截图", "スクリーンショット", "스크린샷", "Снимки экрана"],
    "App": ["Application", "App", "App", "App", "App", "应用", "アプリ", "앱", "Приложение"],
    "Copy screenshots automatically": ["Copier les captures automatiquement", "Copiar capturas automáticamente", "Bildschirmfotos automatisch kopieren", "Copia automaticamente gli screenshot", "Copiar capturas automaticamente", "自动复制截图", "スクリーンショットを自動でコピー", "스크린샷 자동 복사", "Автоматически копировать снимки"],
    "Launch at login": ["Ouvrir au démarrage", "Abrir al iniciar sesión", "Beim Anmelden öffnen", "Apri al login", "Abrir ao iniciar sessão", "登录时打开", "ログイン時に起動", "로그인 시 열기", "Запускать при входе"],
    "Show screenshot thumbnail": ["Afficher la vignette", "Mostrar miniatura", "Miniatur anzeigen", "Mostra miniatura", "Mostrar miniatura", "显示截图缩略图", "サムネールを表示", "썸네일 표시", "Показывать миниатюру"],
    "macOS shows the preview in the corner, but copying waits about 5 seconds.": ["macOS affiche l'aperçu dans le coin, mais la copie attend environ 5 secondes.", "macOS muestra la vista previa en la esquina, pero la copia espera unos 5 segundos.", "macOS zeigt die Vorschau in der Ecke, aber das Kopieren wartet etwa 5 Sekunden.", "macOS mostra l'anteprima nell'angolo, ma la copia attende circa 5 secondi.", "O macOS mostra a prévia no canto, mas a cópia espera cerca de 5 segundos.", "macOS 会在角落显示预览，但复制会等待约 5 秒。", "隅にプレビューが表示されますが、コピーは約5秒遅れます。", "모서리에 미리보기가 표시되지만 복사가 약 5초 지연됩니다.", "macOS показывает превью в углу, но копирование ждёт около 5 секунд."],
    "Delete file after copying": ["Supprimer le fichier après copie", "Eliminar el archivo tras copiar", "Datei nach dem Kopieren löschen", "Elimina il file dopo la copia", "Excluir o arquivo após copiar", "复制后删除文件", "コピー後にファイルを削除", "복사 후 파일 삭제", "Удалять файл после копирования"],
    "The file goes to the Trash once it's in your clipboard. It stays in the history.": ["Le fichier part à la Corbeille une fois copié. Il reste dans l'historique.", "El archivo va a la Papelera una vez copiado. Sigue en el historial.", "Die Datei wird nach dem Kopieren in den Papierkorb gelegt. Sie bleibt im Verlauf.", "Il file va nel Cestino dopo la copia. Resta nella cronologia.", "O arquivo vai para a Lixeira depois de copiado. Continua no histórico.", "文件复制后会移到废纸篓，但仍保留在历史记录中。", "コピー後にファイルはゴミ箱に移動します。履歴には残ります。", "복사 후 파일은 휴지통으로 이동하며 기록에는 남습니다.", "После копирования файл попадёт в Корзину, но останется в истории."],
    "Screenshot folder": ["Dossier des captures", "Carpeta de capturas", "Bildschirmfoto-Ordner", "Cartella screenshot", "Pasta de capturas", "截图文件夹", "保存先フォルダ", "스크린샷 폴더", "Папка снимков"],
    "Show in Finder": ["Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen", "Mostra nel Finder", "Mostrar no Finder", "在访达中显示", "Finderで表示", "Finder에서 보기", "Показать в Finder"],
    "History menu": ["Menu Historique", "Menú Historial", "Verlaufsmenü", "Menu Cronologia", "Menu Histórico", "历史记录菜单", "履歴メニュー", "기록 메뉴", "Меню истории"],
    "Click to copy": ["Copier au clic", "Copiar al hacer clic", "Zum Kopieren klicken", "Copia con un clic", "Copiar ao clicar", "点按即复制", "クリックでコピー", "클릭하여 복사", "Копировать по нажатию"],
    "Clicking a screenshot in the History menu copies it. When off, it opens in Preview.": ["Un clic sur une capture du menu Historique la copie. Désactivé : elle s'ouvre dans Aperçu.", "Al hacer clic en una captura del menú Historial se copia. Si está desactivado, se abre en Vista Previa.", "Ein Klick auf ein Bildschirmfoto im Verlauf kopiert es. Wenn aus, wird es in Vorschau geöffnet.", "Facendo clic su uno screenshot nella Cronologia lo copi. Se disattivato, si apre in Anteprima.", "Clicar em uma captura no menu Histórico a copia. Se desativado, ela abre no Pré-Visualização.", "在“历史记录”菜单中点按截图即可复制。关闭后将在“预览”中打开。", "履歴メニューのスクリーンショットをクリックするとコピーします。オフの場合はプレビューで開きます。", "기록 메뉴에서 스크린샷을 클릭하면 복사됩니다. 끄면 미리보기에서 열립니다.", "Нажатие на снимок в меню «История» копирует его. Если выключено — открывает в Просмотре."],
    "Screenshots shown in menu": ["Captures affichées dans le menu", "Capturas mostradas en el menú", "Bildschirmfotos im Menü", "Screenshot mostrati nel menu", "Capturas exibidas no menu", "菜单中显示的截图数", "メニューに表示する数", "메뉴에 표시할 개수", "Снимков в меню"],
    "Storage": ["Stockage", "Almacenamiento", "Speicher", "Archiviazione", "Armazenamento", "存储", "保存", "저장 공간", "Хранилище"],
    "Saved screenshots": ["Captures enregistrées", "Capturas guardadas", "Gespeicherte Bildschirmfotos", "Screenshot salvati", "Capturas salvas", "已保存的截图", "保存済みのスクリーンショット", "저장된 스크린샷", "Сохранено снимков"],
    "Skip Trash when clearing": ["Ne pas passer par la Corbeille", "Omitir la Papelera al borrar", "Papierkorb beim Löschen überspringen", "Salta il Cestino quando cancelli", "Ignorar a Lixeira ao limpar", "清除时不经过废纸篓", "消去時にゴミ箱を使わない", "지울 때 휴지통 건너뛰기", "Удалять мимо Корзины"],
    "Check automatically at launch": ["Vérifier automatiquement au lancement", "Buscar automáticamente al abrir", "Beim Start automatisch prüfen", "Controlla automaticamente all'avvio", "Verificar automaticamente ao abrir", "启动时自动检查", "起動時に自動で確認", "실행 시 자동으로 확인", "Проверять при запуске"],
    "Check Now": ["Vérifier maintenant", "Buscar ahora", "Jetzt prüfen", "Controlla ora", "Verificar agora", "立即检查", "今すぐ確認", "지금 확인", "Проверить сейчас"],
    "Checking…": ["Vérification…", "Buscando…", "Wird geprüft…", "Controllo…", "Verificando…", "正在检查…", "確認中…", "확인 중…", "Проверка…"],
    "You're up to date.": ["ScreenClip est à jour.", "Tienes la última versión.", "Du bist auf dem neuesten Stand.", "Hai l'ultima versione.", "Você está atualizado.", "已是最新版本。", "最新の状態です。", "최신 버전입니다.", "Установлена последняя версия."],
    "Version %@ is available.": ["La version %@ est disponible.", "La versión %@ está disponible.", "Version %@ ist verfügbar.", "La versione %@ è disponibile.", "A versão %@ está disponível.", "版本 %@ 已推出。", "バージョン %@ が利用可能です。", "버전 %@을(를) 사용할 수 있습니다.", "Доступна версия %@."],
    "Update Now": ["Mettre à jour", "Actualizar ahora", "Jetzt aktualisieren", "Aggiorna ora", "Atualizar agora", "立即更新", "今すぐアップデート", "지금 업데이트", "Обновить"],
    "Downloading…": ["Téléchargement…", "Descargando…", "Wird geladen…", "Download…", "Baixando…", "正在下载…", "ダウンロード中…", "다운로드 중…", "Загрузка…"],
    "Installing…": ["Installation…", "Instalando…", "Wird installiert…", "Installazione…", "Instalando…", "正在安装…", "インストール中…", "설치 중…", "Установка…"],
    "Couldn't check for updates.": ["Impossible de vérifier les mises à jour.", "No se pudieron buscar actualizaciones.", "Updates konnten nicht geprüft werden.", "Impossibile controllare gli aggiornamenti.", "Não foi possível verificar atualizações.", "无法检查更新。", "アップデートを確認できませんでした。", "업데이트를 확인할 수 없습니다.", "Не удалось проверить обновления."],
    "Update failed.": ["La mise à jour a échoué.", "La actualización falló.", "Update fehlgeschlagen.", "Aggiornamento non riuscito.", "A atualização falhou.", "更新失败。", "アップデートに失敗しました。", "업데이트에 실패했습니다.", "Не удалось обновить."],
    "Version %@": ["Version %@", "Versión %@", "Version %@", "Versione %@", "Versão %@", "版本 %@", "バージョン %@", "버전 %@", "Версия %@"],
    "View on GitHub": ["Voir sur GitHub", "Ver en GitHub", "Auf GitHub ansehen", "Vedi su GitHub", "Ver no GitHub", "在 GitHub 上查看", "GitHubで見る", "GitHub에서 보기", "Открыть на GitHub"],
    "Copies your Mac screenshots straight to the clipboard.": ["Copie tes captures d'écran directement dans le presse-papier.", "Copia tus capturas de pantalla directamente al portapapeles.", "Kopiert deine Bildschirmfotos direkt in die Zwischenablage.", "Copia i tuoi screenshot direttamente negli appunti.", "Copia suas capturas de tela direto para a área de transferência.", "将 Mac 截图直接复制到剪贴板。", "Macのスクリーンショットをそのままクリップボードにコピーします。", "Mac 스크린샷을 바로 클립보드에 복사합니다.", "Копирует снимки экрана Mac прямо в буфер обмена."],
    "What's new": ["Nouveautés", "Novedades", "Neuigkeiten", "Novità", "Novidades", "新功能", "新機能", "새로운 기능", "Что нового"],
    "ScreenClip will restart to finish updating.": ["ScreenClip va redémarrer pour terminer la mise à jour.", "ScreenClip se reiniciará para terminar la actualización.", "ScreenClip wird neu gestartet, um das Update abzuschließen.", "ScreenClip si riavvierà per completare l'aggiornamento.", "O ScreenClip será reiniciado para concluir a atualização.", "ScreenClip 将重新启动以完成更新。", "アップデートを完了するためにScreenClipを再起動します。", "업데이트를 완료하기 위해 ScreenClip이 다시 시작됩니다.", "ScreenClip перезапустится, чтобы завершить обновление."],
]

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PopoutComponent {
            id: popout
            required property var controller
            readonly property var root: controller
            function t(key, fallback, args) { return controller.t(key, fallback, args); }
            function scrollToProvider(providerId) {
                for (let i = 0; i < providerCardsRepeater.count; i++) {
                    const item = providerCardsRepeater.itemAt(i);
                    if (item && item.provider && item.provider.provider === providerId) {
                        const y = item.mapToItem(contentColumn, 0, 0).y;
                        const maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height);
                        scrollFocusAnim.from = contentFlick.contentY;
                        scrollFocusAnim.to = Math.min(Math.max(0, y - Theme.spacingM), maxY);
                        scrollFocusAnim.restart();
                        break;
                    }
                }
            }
            NumberAnimation {
                id: scrollFocusAnim
                target: contentFlick
                property: "contentY"
                duration: 360
                easing.type: Easing.OutCubic
            }

            // The stock header is replaced by the brand card below.
            headerText: ""
            detailsText: ""
            showCloseButton: false

            // Label of the header action under the cursor; the subtitle shows
            // it in place of the status line, since the buttons are icon-only.
            property string hoveredAction: ""

            StyledRect {
                id: brandHeader
                width: parent.width
                height: root.costCurrency === "USD" ? 68 : 86
                radius: Theme.cornerRadius + 4
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.14)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: Theme.withAlpha(Theme.primary, 0.12)
                        }
                        GradientStop {
                            position: 0.6
                            color: Theme.withAlpha(Theme.primary, 0.02)
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 44
                        height: 44
                        radius: width / 2
                        color: Theme.withAlpha(Theme.primary, 0.16)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.28)

                        // White silhouette tinted to the theme accent, so the
                        // mascot keeps contrast on every palette.
                        Image {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            source: Qt.resolvedUrl("assets/logo.png")
                            sourceSize: Qt.size(60, 60)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.primary
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: implicitWidth > width
                                Layout.maximumWidth: implicitWidth
                                text: t("app.title", "AI Usage Control")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                // Manifest version pill: reads plugin.json at runtime,
                                // so it stays correct across store and manual installs.
                                visible: root.pluginVersion.length > 0
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: popoutVersionLabel.implicitWidth + Theme.spacingS * 2
                                implicitHeight: 20
                                radius: 10
                                color: Theme.withAlpha(Theme.primary, 0.12)
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.primary, 0.24)

                                StyledText {
                                    id: popoutVersionLabel
                                    anchors.centerIn: parent
                                    text: "v" + root.pluginVersion
                                    color: Theme.primary
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    font.weight: Font.DemiBold
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        StyledText {
                            visible: root.costCurrency !== "USD"
                            Layout.fillWidth: true
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                            elide: Text.ElideRight
                            text: {
                                const money = root.moneyFormatter;
                                if (!money || !money.available)
                                    return t("currency.status.unavailable", "Exchange rate unavailable; costs shown in USD");
                                return money.stale
                                    ? t("currency.status.stale", "Estimated {currency} costs · cached FX {date}", {currency: root.costCurrency, date: money.sourceDate})
                                    : t("currency.status.current", "Estimated {currency} costs · FX {date}", {currency: root.costCurrency, date: money.sourceDate});
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: headerStatusText.implicitHeight
                            clip: true

                            StyledText {
                                id: headerStatusText
                                width: parent.width
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: popout.hoveredAction.length > 0 ? Theme.primary : (root.isDataStale || root.hasError ? Theme.warning : Theme.surfaceVariantText)
                                elide: Text.ElideRight

                                readonly property string targetText: {
                                    if (popout.hoveredAction.length > 0)
                                        return popout.hoveredAction;
                                    if (root.lastUpdated.length === 0)
                                        return t("popout.provider_dashboard", "Provider dashboard");
                                    return root.isDataStale ? t("popout.details_stale", "Stale since {time} · local adapters", {
                                        time: root.lastUpdated
                                    }) : t("popout.details_updated", "Updated {time} · local adapters", {
                                        time: root.lastUpdated
                                    });
                                }

                                Component.onCompleted: text = targetText
                                onTargetTextChanged: if (text !== targetText)
                                    statusFlip.restart()

                                SequentialAnimation {
                                    id: statusFlip
                                    ParallelAnimation {
                                        NumberAnimation {
                                            target: headerStatusText
                                            property: "opacity"
                                            to: 0
                                            duration: 90
                                        }
                                        NumberAnimation {
                                            target: headerStatusText
                                            property: "y"
                                            to: 6
                                            duration: 90
                                            easing.type: Easing.InQuad
                                        }
                                    }
                                    PropertyAction {
                                        target: headerStatusText
                                        property: "text"
                                        value: headerStatusText.targetText
                                    }
                                    PropertyAction {
                                        target: headerStatusText
                                        property: "y"
                                        value: -6
                                    }
                                    ParallelAnimation {
                                        NumberAnimation {
                                            target: headerStatusText
                                            property: "opacity"
                                            to: 1
                                            duration: 140
                                        }
                                        NumberAnimation {
                                            target: headerStatusText
                                            property: "y"
                                            to: 0
                                            duration: 140
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Segmented capsule: community links, then plugin actions.
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        HeaderAction {
                            position: "first"
                            iconName: "favorite"
                            accent: Theme.error
                            label: t("header.upvote", "Upvote on the DankLinux plugin registry")
                            onHoveredChanged: popout.hoveredAction = hovered ? label : ""
                            onTriggered: Qt.openUrlExternally("https://github.com/AvengeMedia/dms-plugin-registry/issues/358")
                        }

                        HeaderAction {
                            iconName: "code"
                            label: t("header.repo", "Source code on GitHub")
                            onHoveredChanged: popout.hoveredAction = hovered ? label : ""
                            onTriggered: Qt.openUrlExternally("https://github.com/bernardopg/AiOverviewControl")
                        }

                        HeaderAction {
                            iconName: "refresh"
                            hoverRotation: 180
                            spinning: root.isLoading
                            actionEnabled: root.binaryReady && !root.isLoading
                            label: t("card.refresh", "Refresh")
                            onHoveredChanged: popout.hoveredAction = hovered ? label : ""
                            onTriggered: root.refresh()
                        }

                        HeaderAction {
                            position: "last"
                            iconName: "settings"
                            hoverRotation: 90
                            label: t("header.settings", "Plugin settings")
                            onHoveredChanged: popout.hoveredAction = hovered ? label : ""
                            onTriggered: {
                                if (popout.closePopout)
                                    popout.closePopout();
                                root.openSettingsWindow();
                            }
                        }
                    }

                    HeaderAction {
                        Layout.alignment: Qt.AlignVCenter
                        position: "single"
                        iconName: "close"
                        accent: Theme.error
                        hoverRotation: 90
                        label: t("header.close", "Close")
                        onHoveredChanged: popout.hoveredAction = hovered ? label : ""
                        onTriggered: if (popout.closePopout)
                            popout.closePopout()
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.spacingM
            }

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - brandHeader.height - Theme.spacingM - Theme.spacingXL

                Flickable {
                    id: contentFlick
                    anchors.fill: parent
                    anchors.leftMargin: popout.width < 620 ? Theme.spacingS : Theme.spacingL
                    anchors.rightMargin: popout.width < 620 ? Theme.spacingS : Theme.spacingL
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: contentColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar {
                        id: contentScrollBar
                        policy: contentFlick.contentHeight > contentFlick.height ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 0
                        width: 10
                        padding: 2
                        // Thin, rounded handle that brightens on hover/drag and
                        // fades out when idle so it never competes with the cards.
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: width / 2
                            color: Theme.withAlpha(Theme.surfaceText, contentScrollBar.pressed ? 0.5 : (contentScrollBar.hovered ? 0.34 : 0.2))
                            opacity: (contentScrollBar.active || contentScrollBar.policy === ScrollBar.AlwaysOn || contentScrollBar.hovered) ? 1 : 0
                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        background: Rectangle {
                            implicitWidth: 6
                            radius: width / 2
                            color: Theme.withAlpha(Theme.surfaceText, 0.05)
                            opacity: contentScrollBar.hovered || contentScrollBar.pressed ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 220
                                }
                            }
                        }
                    }

                    Column {
                        id: contentColumn
                        // Reserve only the slim scrollbar plus a hair of gap, so the
                        // cards keep a symmetric inset instead of a wide right gutter.
                        width: contentFlick.width - contentScrollBar.width - 2
                        spacing: Theme.spacingL

                        Item {
                            width: parent.width
                            height: 3
                            visible: root.isLoading
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: Theme.withAlpha(Theme.primary, 0.12)
                            }

                            Rectangle {
                                id: loadRunner
                                width: Math.max(48, parent.width * 0.24)
                                height: parent.height
                                radius: 1.5
                                color: Theme.primary

                                SequentialAnimation on x {
                                    running: root.isLoading
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: -loadRunner.width
                                        to: contentColumn.width
                                        duration: 1200
                                        easing.type: Easing.InOutCubic
                                    }
                                }
                            }
                        }

                        StyledRect {
                            id: heroCard
                            width: parent.width
                            radius: Theme.cornerRadius + 8
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, 0.3)
                            implicitHeight: overviewCol.implicitHeight + (contentColumn.width < 560 ? Theme.spacingL : Theme.spacingXL) * 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Theme.withAlpha(root.heroAccent, 0.18)
                                    }
                                    GradientStop {
                                        position: 0.52
                                        color: Theme.withAlpha(root.heroAccent, 0.055)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: Theme.withAlpha(Theme.surfaceContainer, 0.02)
                                    }
                                }
                            }

                            // Slow ambient glow drifting behind the content, tinted by usage.
                            Rectangle {
                                id: heroGlow
                                width: parent.width * 0.55
                                height: width
                                radius: width / 2
                                y: -height * 0.55
                                color: Theme.withAlpha(root.heroAccent, 0.09)
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 600
                                    }
                                }

                                SequentialAnimation on x {
                                    // Only burn cycles while the popout is actually on screen;
                                    // parentPopout is injected by PluginPopout's Loader.
                                    running: popout.parentPopout ? popout.parentPopout.shouldBeVisible : false
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: -heroGlow.width * 0.3
                                        to: heroCard.width - heroGlow.width * 0.7
                                        duration: 14000
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        from: heroCard.width - heroGlow.width * 0.7
                                        to: -heroGlow.width * 0.3
                                        duration: 14000
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                            opacity: 0
                            transform: Translate {
                                id: heroShift
                                y: 10
                            }
                            Component.onCompleted: heroIntro.start()

                            ParallelAnimation {
                                id: heroIntro
                                NumberAnimation {
                                    target: heroCard
                                    property: "opacity"
                                    to: 1
                                    duration: 380
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: heroShift
                                    property: "y"
                                    to: 0
                                    duration: 480
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Column {
                                id: overviewCol
                                anchors.fill: parent
                                anchors.margins: contentColumn.width < 560 ? Theme.spacingL : Theme.spacingXL
                                spacing: Theme.spacingL

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    // Provider mark wrapped in its primary-window ring: the same number
                                    // as the bars, read at a glance before the text.
                                    Item {
                                        Layout.alignment: Qt.AlignTop
                                        width: 56
                                        height: 56

                                        ProgressRing {
                                            anchors.fill: parent
                                            percent: root.hasProviderData ? root.primaryPercent : 0
                                            thickness: 4
                                            accentColor: root.heroAccent
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 42
                                            height: 42
                                            radius: width / 2
                                            color: Theme.withAlpha(root.heroAccent, 0.14)
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 400
                                                }
                                            }

                                            SequentialAnimation on scale {
                                                running: root.isLoading
                                                loops: Animation.Infinite
                                                alwaysRunToEnd: true
                                                NumberAnimation {
                                                    to: 0.9
                                                    duration: 520
                                                    easing.type: Easing.InOutQuad
                                                }
                                                NumberAnimation {
                                                    to: 1.0
                                                    duration: 520
                                                    easing.type: Easing.InOutQuad
                                                }
                                            }

                                            ProviderLogo {
                                                anchors.centerIn: parent
                                                visible: root.hasProviderData
                                                providerId: root.providerData ? root.providerData.provider : ""
                                                logoSize: 22
                                                tintColor: root.heroAccent
                                            }

                                            Image {
                                                anchors.centerIn: parent
                                                visible: !root.hasProviderData
                                                width: 26
                                                height: 26
                                                source: Qt.resolvedUrl("assets/logo.png")
                                                sourceSize: Qt.size(52, 52)
                                                fillMode: Image.PreserveAspectFit
                                                mipmap: true
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: Theme.primary
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: Theme.spacingS

                                        Row {
                                            spacing: Theme.spacingXS

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: root.hasError ? Theme.warning : (root.hasProviderData ? Theme.success : Theme.surfaceVariantText)

                                                SequentialAnimation on opacity {
                                                    running: root.isLoading
                                                    loops: Animation.Infinite
                                                    NumberAnimation {
                                                        from: 1
                                                        to: 0.3
                                                        duration: 620
                                                        easing.type: Easing.InOutQuad
                                                    }
                                                    NumberAnimation {
                                                        from: 0.3
                                                        to: 1
                                                        duration: 620
                                                        easing.type: Easing.InOutQuad
                                                    }
                                                }
                                            }

                                            StyledText {
                                                text: root.statusTitle.toUpperCase()
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 1.2
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: root.providerData ? root.providerName(root.providerData.provider) : t("app.title", "AI Usage Control")
                                            color: Theme.surfaceText
                                            font.pixelSize: contentColumn.width < 560 ? Theme.fontSizeLarge + 2 : Theme.fontSizeLarge + 6
                                            font.weight: Font.Bold
                                            wrapMode: Text.WordWrap
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: root.statusSubtitle
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeMedium
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingXS

                                            BadgePill {
                                                label: root.providerData ? root.providerSourceLabel(root.providerData) : t("status.local_helpers", "local adapters")
                                                iconName: "sync_alt"
                                                accentColor: Theme.primary
                                            }

                                            BadgePill {
                                                visible: !!root.providerData && !root.isPlainProvider(root.providerData.provider)
                                                label: root.providerData ? root.providerKindsLabel(root.providerData.provider) : ""
                                                iconName: root.providerData ? root.providerKindIconFor(root.providerData.provider) : "cloud"
                                                accentColor: root.providerData ? root.providerKindAccentFor(root.providerData.provider) : Theme.primary
                                            }

                                            BadgePill {
                                                label: root.hasError && !root.hasProviderData ? t("status.setup_required", "Setup required") : root.hasError ? t("status.needs_attention", "Needs attention") : root.providerStatusLabel(root.providerData)
                                                iconName: root.hasError ? "warning" : "check_circle"
                                                accentColor: root.hasError ? Theme.warning : root.getUsageColor(root.primaryPercent)
                                            }

                                            BadgePill {
                                                visible: root.isDataStale
                                                label: t("status.stale", "Stale")
                                                iconName: "schedule"
                                                accentColor: Theme.warning
                                                emphasized: true
                                            }
                                        }
                                    }

                                    // Window bars double as a jump link to the focused provider's card.
                                    Item {
                                        visible: contentColumn.width >= 480 && root.hasProviderData && root.windowsForProvider(root.providerData).length > 0
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: Math.min(260, contentColumn.width * 0.44)
                                        implicitHeight: heroBarsCol.implicitHeight

                                        Column {
                                            id: heroBarsCol
                                            width: parent.width
                                            spacing: Theme.spacingM
                                            opacity: heroBarsJump.containsMouse ? 0.82 : 1
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 120
                                                }
                                            }

                                            Repeater {
                                                model: root.windowsForProvider(root.providerData)

                                                UsageBar {
                                                    required property var modelData
                                                    width: parent.width
                                                    label: modelData.label
                                                    percent: Number(modelData.data.usedPercent || 0)
                                                    aside: root.formatUsageLine(modelData.data)
                                                    accentColor: root.getUsageColor(Number(modelData.data.usedPercent || 0))
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: heroBarsJump
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.focusProvider(root.providerData ? root.providerData.provider : "")
                                        }
                                    }

                                    // Guided hint that fills the window-bar slot when there is no
                                    // focused provider — covers loading, all-providers-errored, and
                                    // no-data-yet so the hero never reads as a blank panel.
                                    Row {
                                        visible: contentColumn.width >= 480 && !root.hasProviderData
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: Math.min(260, contentColumn.width * 0.44)
                                        spacing: Theme.spacingS

                                        readonly property color hintAccent: root.isLoading ? Theme.primary : (root.errorProviders.length > 0 ? Theme.warning : root.heroAccent)

                                        Rectangle {
                                            width: 34
                                            height: 34
                                            radius: 11
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.withAlpha(parent.hintAccent, 0.14)
                                            border.width: 1
                                            border.color: Theme.withAlpha(parent.hintAccent, 0.28)

                                            DankIcon {
                                                anchors.centerIn: parent
                                                name: root.isLoading ? "hourglass_top" : (root.errorProviders.length > 0 ? "warning" : "monitoring")
                                                size: 17
                                                color: parent.parent.hintAccent
                                            }
                                        }

                                        Column {
                                            width: parent.width - 34 - Theme.spacingS
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                text: root.isLoading ? t("status.syncing", "Syncing usage") : (root.errorProviders.length > 0 ? t("hero.error_title", "All providers need attention") : t("hero.empty_title", "No usage data yet"))
                                                color: Theme.surfaceText
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Bold
                                                wrapMode: Text.WordWrap
                                            }

                                            StyledText {
                                                width: parent.width
                                                text: root.isLoading ? t("status.loading_usage", "Fetching provider usage data...") : (root.errorProviders.length > 0 ? t("hero.error_body", "Check credentials and that the provider CLIs are installed.") : t("status.no_data_hint", "Run your configured AI CLIs and refresh to populate usage windows."))
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: Theme.fontSizeSmall
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }

                                // One stat strip for the whole fleet. Fleet-wide figures only appear
                                // with 2+ live providers; the focused reset covers the single case.
                                StyledRect {
                                    width: parent.width
                                    radius: Theme.cornerRadius + 2
                                    color: Theme.withAlpha(Theme.surfaceText, 0.035)
                                    border.width: 1
                                    border.color: Theme.withAlpha(Theme.surfaceText, 0.07)
                                    implicitHeight: statFlow.implicitHeight + Theme.spacingM * 2

                                    Flow {
                                        id: statFlow
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingL

                                        HeroStat {
                                            visible: root.fleetRollup.count >= 2
                                            ringPercent: root.fleetRollup.avg
                                            statIcon: "speed"
                                            statLabel: t("rollup.avg_load", "Avg load")
                                            statValue: `${Math.round(root.fleetRollup.avg)}%`
                                            statAccent: root.getUsageColor(root.fleetRollup.avg)
                                        }

                                        // Peak provider is a jump link: click to expand + scroll to its card.
                                        HeroStat {
                                            visible: root.fleetRollup.count >= 2
                                            statIcon: "local_fire_department"
                                            statLabel: root.fleetRollup.peakName.length > 0 ? root.fleetRollup.peakName : t("rollup.peak", "Peak")
                                            statValue: `${Math.round(root.fleetRollup.peak)}%`
                                            statAccent: root.getUsageColor(root.fleetRollup.peak)
                                            clickable: root.fleetRollup.peakId.length > 0
                                            onClicked: root.focusProvider(root.fleetRollup.peakId)
                                        }

                                        HeroStat {
                                            statIcon: "check_circle"
                                            statLabel: t("card.active", "Active")
                                            statValue: String(root.successfulProviders.length)
                                            statAccent: Theme.success
                                        }

                                        HeroStat {
                                            statIcon: "error"
                                            statLabel: t("card.attention", "Attention")
                                            statValue: String(root.errorProviders.length)
                                            statAccent: root.errorProviders.length > 0 ? Theme.warning : Theme.success
                                        }

                                        HeroStat {
                                            visible: root.fleetRollup.count >= 2
                                            statIcon: "warning"
                                            statLabel: t("rollup.at_risk", "At risk")
                                            statValue: String(root.fleetRollup.atRisk)
                                            statAccent: root.fleetRollup.atRisk > 0 ? Theme.error : Theme.success
                                        }

                                        HeroStat {
                                            readonly property bool fleet: root.fleetRollup.count >= 2
                                            visible: fleet ? root.fleetRollup.nextResetMs > 0 : !!(root.primaryWindow && root.primaryWindow.resetsAt)
                                            statIcon: "schedule"
                                            statLabel: fleet ? t("rollup.next_reset", "Next reset") : t("card.resets_in", "Resets in")
                                            statValue: fleet ? root.fleetNextResetLabel : (root.primaryWindow ? root.formatTimeUntil(root.primaryWindow.resetsAt) : "—")
                                            statAccent: root.heroAccent
                                        }

                                        HeroStat {
                                            statIcon: "history"
                                            statLabel: t("popout.last_sync", "Last sync")
                                            statValue: root.lastUpdated.length > 0 ? root.lastUpdated : "—"
                                            statAccent: root.isDataStale ? Theme.warning : Theme.primary
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: root.providers.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    Layout.fillWidth: true
                                    text: t("card.providers", "Providers")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Font.Bold
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: providerCountLabel.implicitWidth + Theme.spacingM * 2
                                    implicitHeight: 28
                                    radius: 14
                                    color: Theme.withAlpha(root.heroAccent, 0.12)
                                    border.width: 1
                                    border.color: Theme.withAlpha(root.heroAccent, 0.24)

                                    StyledText {
                                        id: providerCountLabel
                                        anchors.centerIn: parent
                                        text: root.filteredDisplayProviders.length === 1 ? t("status.displayed", "{count} displayed", {
                                            count: root.filteredDisplayProviders.length
                                        }) : t("status.displayed_plural", "{count} displayed", {
                                            count: root.filteredDisplayProviders.length
                                        })
                                        color: root.heroAccent
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.DemiBold
                                    }
                                }

                                DankActionButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    iconName: root.allExpanded ? "unfold_less" : "unfold_more"
                                    iconColor: root.allExpanded ? Theme.primary : Theme.surfaceVariantText
                                    backgroundColor: Theme.withAlpha(Theme.primary, root.allExpanded ? 0.12 : 0.06)
                                    buttonSize: 30
                                    tooltipText: root.allExpanded ? t("card.collapse_all", "Collapse all") : t("card.expand_all", "Expand all")
                                    onClicked: {
                                        root.allExpanded = !root.allExpanded;
                                        if (root.allExpanded)
                                            root.focusedProviderId = "";
                                    }
                                }
                            }

                            DankFilterChips {
                                width: parent.width
                                showCounts: true
                                model: [
                                    {
                                        label: t("filter.all", "All"),
                                        count: root.displayProviders.length
                                    },
                                    {
                                        label: t("filter.live", "Live"),
                                        count: root.successfulProviders.length
                                    },
                                    {
                                        label: t("filter.issues", "Issues"),
                                        count: root.errorProviders.length
                                    }
                                ]
                                onSelectionChanged: index => root.providerStatusFilter = index === 1 ? "live" : (index === 2 ? "issues" : "all")
                            }
                        }

                        StyledText {
                            visible: root.isLoading && root.providers.length === 0
                            width: parent.width
                            text: t("status.loading_usage", "Fetching provider usage data...")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledRect {
                            visible: !root.isLoading && root.providers.length === 0
                            width: parent.width
                            radius: Theme.cornerRadius + 6
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.withAlpha(root.heroAccent, 0.18)
                            implicitHeight: emptyStateCol.implicitHeight + Theme.spacingL * 2

                            Column {
                                id: emptyStateCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingL
                                spacing: Theme.spacingM

                                RowLayout {
                                    width: parent.width
                                    spacing: Theme.spacingM

                                    Rectangle {
                                        Layout.alignment: Qt.AlignTop
                                        width: 36
                                        height: 36
                                        radius: 18
                                        color: Theme.withAlpha(root.heroAccent, 0.14)
                                        border.width: 1
                                        border.color: Theme.withAlpha(root.heroAccent, 0.28)

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "monitoring"
                                            size: 18
                                            color: root.heroAccent
                                        }
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        StyledText {
                                            width: parent.width
                                            text: t("status.no_provider_data", "No provider data available. Check credentials and local provider CLIs.")
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                        }

                                        StyledText {
                                            width: parent.width
                                            text: t("status.no_data_hint", "Run your configured AI CLIs and refresh to populate usage windows.")
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Flow {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    BadgePill {
                                        label: t("card.refresh", "Refresh")
                                        iconName: "refresh"
                                        accentColor: Theme.primary
                                        emphasized: true
                                        onTapped: root.refresh()
                                    }

                                    BadgePill {
                                        label: root.t("settings.configured_count", "{count} configured", {
                                            count: root.selectedProviders.length
                                        })
                                        iconName: "playlist_add_check"
                                        accentColor: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }

                        ProviderManager {
                            width: parent.width
                        }

                        DankTextField {
                            visible: root.displayProviders.length > 5
                            width: parent.width
                            placeholderText: t("card.filter_providers", "Filter providers by name or source")
                            text: root.providerFilter
                            onTextChanged: root.providerFilter = text
                        }

                        Repeater {
                            id: providerCardsRepeater
                            model: root.filteredDisplayProviders

                            ProviderDashboardCard {
                                required property var modelData
                                provider: modelData
                            }
                        }
                    }
                }
            }

    component SurfaceButton: StyledRect {
        id: buttonRoot

        required property string iconName
        required property string label
        property string description: ""
        property bool compact: false
        property bool prominent: false
        property bool actionEnabled: true

        signal triggered

        implicitWidth: compact ? Math.max(104, buttonLabel.implicitWidth + 24 + Theme.spacingXS + Theme.spacingS * 2 + 2) : 176
        implicitHeight: compact ? 40 : (description.length > 0 ? 56 : 48)
        radius: Theme.cornerRadius
        color: {
            if (!actionEnabled) {
                return Theme.surfaceContainer;
            }
            if (prominent) {
                return Theme.primaryContainer;
            }
            return buttonMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer;
        }
        border.width: 1
        border.color: {
            if (buttonRoot.activeFocus) {
                return Theme.primary;
            }
            if (prominent) {
                return Theme.withAlpha(Theme.primary, 0.38);
            }
            return buttonMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.18) : Theme.outlineVariant;
        }
        opacity: actionEnabled ? 1 : 0.54
        scale: actionEnabled && buttonMouse.containsMouse ? 1.01 : 1.0
        clip: true

        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 140
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 140
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.rightMargin: compact ? Theme.spacingS : Theme.spacingM
            anchors.topMargin: compact ? Theme.spacingXS : Theme.spacingM
            anchors.bottomMargin: compact ? Theme.spacingXS : Theme.spacingM
            spacing: compact ? Theme.spacingXS : Theme.spacingS

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: compact ? 24 : 32
                height: compact ? 24 : 32
                radius: width / 2
                color: buttonRoot.prominent ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.surfaceText, 0.08)

                DankIcon {
                    anchors.centerIn: parent
                    name: buttonRoot.iconName
                    size: compact ? 14 : 18
                    color: buttonRoot.prominent ? Theme.primary : Theme.surfaceText
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: description.length > 0 && !compact ? 2 : 0

                StyledText {
                    id: buttonLabel
                    width: parent.width
                    text: buttonRoot.label
                    wrapMode: Text.NoWrap
                    color: buttonRoot.prominent ? Theme.primary : Theme.surfaceText
                    font.pixelSize: compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: !compact && buttonRoot.description.length > 0
                    width: parent.width
                    text: buttonRoot.description
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            enabled: buttonRoot.actionEnabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
            onClicked: buttonRoot.triggered()
        }
    }

    component BadgePill: StyledRect {
        id: pill

        required property string label
        property string iconName: "circle"
        property color accentColor: Theme.primary
        property bool emphasized: false
        signal tapped

        implicitWidth: pillRow.implicitWidth + Theme.spacingM * 2
        implicitHeight: 28
        radius: 999
        color: emphasized ? Theme.withAlpha(accentColor, 0.16) : Theme.withAlpha(accentColor, 0.1)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, emphasized ? 0.3 : 0.18)

        TapHandler {
            onTapped: pill.tapped()
        }

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DankIcon {
                visible: pill.iconName.length > 0
                name: pill.iconName
                size: 12
                color: pill.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: pill.label
                color: pill.accentColor
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component InfoPill: StyledRect {
        id: ipill

        required property string label
        required property string value
        property color accentColor: Theme.primary
        property string iconName: ""

        implicitWidth: Math.min(ipillRow.implicitWidth + Theme.spacingM * 2, parent ? parent.width : 9999)
        implicitHeight: 26
        radius: 999
        color: Theme.withAlpha(accentColor, 0.08)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.16)

        Row {
            id: ipillRow
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankIcon {
                visible: ipill.iconName.length > 0
                name: ipill.iconName
                size: 12
                color: ipill.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: ipill.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: Math.min(implicitWidth, ipillRow.width - x)
                text: ipill.value.length > 0 ? ipill.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    component MetricTile: Rectangle {
        id: tile

        required property string label
        required property string value
        property color accentColor: Theme.primary
        property bool multilineValue: false

        implicitHeight: multilineValue ? 68 : 58
        radius: Theme.cornerRadius
        color: Theme.withAlpha(accentColor, 0.055)
        border.width: 1
        border.color: Theme.withAlpha(accentColor, 0.16)
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - Theme.spacingS * 2
            radius: width / 2
            color: Theme.withAlpha(accentColor, 0.78)
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: parent.width * 0.32
            height: parent.height
            opacity: 0.42
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.withAlpha(accentColor, 0.12)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.withAlpha(accentColor, 0.0)
                }
            }
        }

        Column {
            id: tileCol
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: 4

            StyledText {
                width: parent.width
                text: tile.label
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.value.length > 0 ? tile.value : "—"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.Bold
                maximumLineCount: tile.multilineValue ? 2 : 1
                wrapMode: tile.multilineValue ? Text.WrapAnywhere : Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }

    component ProgressRing: Item {
        id: ring

        property real percent: 0
        property real thickness: 6
        property color accentColor: Theme.primary
        property color trackColor: Theme.withAlpha(Theme.surfaceText, 0.08)
        // Indirection so the arc sweeps smoothly instead of snapping when new
        // data lands.
        property real animatedPercent: percent

        Behavior on animatedPercent {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutCubic
            }
        }

        onAnimatedPercentChanged: ringCanvas.requestPaint()
        onAccentColorChanged: ringCanvas.requestPaint()
        onTrackColorChanged: ringCanvas.requestPaint()
        onWidthChanged: ringCanvas.requestPaint()
        onHeightChanged: ringCanvas.requestPaint()

        Canvas {
            id: ringCanvas
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const radius = Math.min(width, height) / 2 - ring.thickness / 2;
                if (radius <= 0)
                    return;
                const start = -Math.PI / 2;
                const sweep = Math.max(0, Math.min(1, ring.animatedPercent / 100)) * Math.PI * 2;
                ctx.lineWidth = ring.thickness;
                ctx.lineCap = "round";
                ctx.strokeStyle = String(ring.trackColor);
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.stroke();
                if (sweep > 0.001) {
                    ctx.strokeStyle = String(ring.accentColor);
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, start, start + sweep);
                    ctx.stroke();
                }
            }
        }
    }

    component Sparkline: Item {
        id: spark

        // Points are {t: epochSeconds, p: percent} objects, oldest first.
        property var points: []
        property color lineColor: Theme.primary
        property int hoverIndex: -1

        readonly property real pad: 3
        readonly property real stepX: points && points.length > 1 ? (width - pad * 2) / (points.length - 1) : 0

        function pointPercent(index) {
            const entry = (points || [])[index];
            return Number(entry && entry.p !== undefined ? entry.p : entry) || 0;
        }

        function pointTime(index) {
            const entry = (points || [])[index];
            return entry && entry.t ? Number(entry.t) * 1000 : 0;
        }

        // Left-to-right draw-in on first show.
        property real reveal: 0
        NumberAnimation on reveal {
            from: 0
            to: 1
            duration: 700
            easing.type: Easing.OutCubic
        }
        onRevealChanged: sparkCanvas.requestPaint()

        onPointsChanged: sparkCanvas.requestPaint()
        onLineColorChanged: sparkCanvas.requestPaint()
        onHoverIndexChanged: sparkCanvas.requestPaint()
        onWidthChanged: sparkCanvas.requestPaint()
        onHeightChanged: sparkCanvas.requestPaint()

        Canvas {
            id: sparkCanvas
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const pts = spark.points || [];
                if (pts.length < 2 || width <= 4 || height <= 4)
                    return;
                const pad = spark.pad;
                const w = width - pad * 2;
                const h = height - pad * 2;
                let max = 10;
                for (let i = 0; i < pts.length; i++)
                    max = Math.max(max, spark.pointPercent(i));
                const stepX = w / (pts.length - 1);
                const yFor = v => pad + h - (Math.max(0, Math.min(max, v)) / max) * h;
                const c = spark.lineColor;

                // Faint mid and base guides give the line a scale.
                ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.12);
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 4]);
                ctx.beginPath();
                ctx.moveTo(pad, pad + h / 2 + 0.5);
                ctx.lineTo(pad + w, pad + h / 2 + 0.5);
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.beginPath();
                ctx.moveTo(pad, pad + h + 0.5);
                ctx.lineTo(pad + w, pad + h + 0.5);
                ctx.stroke();

                ctx.save();
                ctx.beginPath();
                ctx.rect(0, 0, width * spark.reveal, height);
                ctx.clip();

                ctx.beginPath();
                ctx.moveTo(pad, yFor(spark.pointPercent(0)));
                for (let i = 1; i < pts.length; i++)
                    ctx.lineTo(pad + i * stepX, yFor(spark.pointPercent(i)));
                const line = String(spark.lineColor);
                ctx.strokeStyle = line;
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.stroke();

                // Soft area fill under the line
                ctx.lineTo(pad + w, pad + h);
                ctx.lineTo(pad, pad + h);
                ctx.closePath();
                const area = ctx.createLinearGradient(0, pad, 0, pad + h);
                area.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.26));
                area.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.0));
                ctx.fillStyle = area;
                ctx.fill();
                ctx.restore();

                if (spark.hoverIndex >= 0) {
                    const hx = pad + spark.hoverIndex * stepX;
                    ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.4);
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(hx, pad);
                    ctx.lineTo(hx, pad + h);
                    ctx.stroke();
                }

                // Highlighted (hovered) or last point dot
                const dotIndex = spark.hoverIndex >= 0 && spark.hoverIndex < pts.length ? spark.hoverIndex : pts.length - 1;
                ctx.beginPath();
                const dotX = pad + dotIndex * stepX;
                const dotY = yFor(spark.pointPercent(dotIndex));
                if (spark.reveal >= 1) {
                    ctx.beginPath();
                    ctx.arc(dotX, dotY, spark.hoverIndex >= 0 ? 6 : 5, 0, Math.PI * 2);
                    ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.22);
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(dotX, dotY, spark.hoverIndex >= 0 ? 3.4 : 2.6, 0, Math.PI * 2);
                    ctx.fillStyle = line;
                    ctx.fill();
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: mouse => {
                if (spark.stepX <= 0)
                    return;
                const index = Math.round((mouse.x - spark.pad) / spark.stepX);
                spark.hoverIndex = Math.max(0, Math.min((spark.points || []).length - 1, index));
            }
            onExited: spark.hoverIndex = -1
        }

        Rectangle {
            visible: spark.hoverIndex >= 0
            x: Math.max(0, Math.min(parent.width - width, spark.pad + spark.hoverIndex * spark.stepX - width / 2))
            y: -height - 2
            implicitWidth: hoverLabel.implicitWidth + Theme.spacingS * 2
            implicitHeight: 20
            radius: 10
            color: Theme.surfaceContainerHighest
            border.width: 1
            border.color: Theme.withAlpha(spark.lineColor, 0.4)

            StyledText {
                id: hoverLabel
                anchors.centerIn: parent
                text: spark.hoverIndex >= 0 ? `${Math.round(spark.pointPercent(spark.hoverIndex))}%${spark.pointTime(spark.hoverIndex) > 0 ? " · " + Qt.formatDateTime(new Date(spark.pointTime(spark.hoverIndex)), "hh:mm") : ""}` : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
            }
        }
    }

    component HeroStat: Item {
        id: heroStat

        required property string statIcon
        required property string statLabel
        required property string statValue
        property color statAccent: Theme.primary
        // >= 0 swaps the icon tile for a progress ring of that percent.
        property real ringPercent: -1
        property bool clickable: false

        signal clicked

        implicitWidth: statRow.implicitWidth
        implicitHeight: statRow.implicitHeight

        // Brief bump whenever the figure changes, so a refresh reads as live.
        onStatValueChanged: valuePulse.restart()

        Row {
            id: statRow
            spacing: Theme.spacingS
            opacity: statMouse.containsMouse ? 0.8 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }

            Rectangle {
                width: 34
                height: 34
                radius: heroStat.ringPercent >= 0 ? 17 : 11
                color: Theme.withAlpha(heroStat.statAccent, heroStat.ringPercent >= 0 ? 0 : 0.12)
                border.width: heroStat.ringPercent >= 0 ? 0 : 1
                border.color: Theme.withAlpha(heroStat.statAccent, 0.2)
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color {
                    ColorAnimation {
                        duration: 300
                    }
                }

                ProgressRing {
                    anchors.fill: parent
                    visible: heroStat.ringPercent >= 0
                    percent: Math.max(0, heroStat.ringPercent)
                    thickness: 4
                    accentColor: heroStat.statAccent
                }

                DankIcon {
                    anchors.centerIn: parent
                    name: heroStat.statIcon
                    size: heroStat.ringPercent >= 0 ? 14 : 16
                    color: heroStat.statAccent
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                StyledText {
                    id: statValueText
                    text: heroStat.statValue
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    transformOrigin: Item.Left

                    SequentialAnimation {
                        id: valuePulse
                        NumberAnimation {
                            target: statValueText
                            property: "scale"
                            to: 1.12
                            duration: 110
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: statValueText
                            property: "scale"
                            to: 1.0
                            duration: 260
                            easing.type: Easing.OutBack
                        }
                    }
                }

                StyledText {
                    text: heroStat.statLabel
                    color: heroStat.clickable && statMouse.containsMouse ? heroStat.statAccent : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.underline: heroStat.clickable && statMouse.containsMouse
                }
            }
        }

        MouseArea {
            id: statMouse
            anchors.fill: parent
            enabled: heroStat.clickable
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: heroStat.clicked()
        }
    }

    component UsageBar: Column {
        id: usageBar
        required property string label
        required property real percent
        property string aside: ""
        property color accentColor: root.getUsageColor(percent)

        width: parent ? parent.width : implicitWidth
        spacing: 6

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width - valueText.implicitWidth - Theme.spacingS
                text: usageBar.label
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            StyledText {
                id: valueText
                text: usageBar.aside.length > 0 ? usageBar.aside : `${Math.round(usageBar.percent)}%`
                wrapMode: Text.NoWrap
                color: usageBar.accentColor
                Behavior on color {
                    ColorAnimation {
                        duration: 300
                    }
                }
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            width: parent.width
            height: 8
            radius: 4
            color: Theme.withAlpha(Theme.surfaceText, 0.075)
            border.width: 1
            border.color: Theme.withAlpha(Theme.surfaceText, 0.045)
            clip: true

            Rectangle {
                id: usageFill
                property bool grown: false
                width: grown ? Math.max(3, Math.min(1, usageBar.percent / 100) * parent.width) : 0
                height: parent.height
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: Theme.withAlpha(usageBar.accentColor, 0.7)
                    }
                    GradientStop {
                        position: 1.0
                        color: usageBar.accentColor
                    }
                }
                Component.onCompleted: Qt.callLater(() => usageFill.grown = true)

                Behavior on width {
                    NumberAnimation {
                        duration: 520
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    component ClaudeDailyBars: DailyBarChart {
        width: parent ? parent.width : implicitWidth
        accent: Theme.primary
        bars: {
            const out = [];
            for (let i = 0; i < 7; i++) {
                out.push({
                    value: Number(root.claudeDailyTokens[i] || 0),
                    primary: root.formatTokens(root.claudeDailyTokens[i] || 0),
                    secondary: root.formatCost(root.claudeDailyCosts[i] || 0),
                    label: root.dayLabels[i],
                    today: i === root.currentWeekdayIndex
                });
            }
            return out;
        }
    }

    component DailyBarChart: Row {
        id: chart

        property var bars: []
        property color accent: Theme.primary
        property real barHeight: 66
        readonly property real maxValue: {
            let top = 0;
            for (let i = 0; i < bars.length; i++)
                top = Math.max(top, Number(bars[i].value || 0));
            return top > 0 ? top : 1;
        }

        spacing: Theme.spacingS

        Repeater {
            model: chart.bars

            Column {
                id: barColumn
                required property var modelData
                required property int index
                width: (chart.width - chart.spacing * Math.max(0, chart.bars.length - 1)) / Math.max(1, chart.bars.length)
                spacing: 7

                Item {
                    id: barSlot
                    width: parent.width
                    height: chart.barHeight

                    readonly property bool today: !!barColumn.modelData.today
                    readonly property bool hovered: dayHover.containsMouse
                    readonly property color barAccent: today ? Theme.warning : chart.accent
                    readonly property real ratio: Number(barColumn.modelData.value || 0) / chart.maxValue
                    readonly property real cap: Theme.cornerRadius - 2
                    property bool grown: false

                    Component.onCompleted: growTimer.start()

                    Timer {
                        id: growTimer
                        interval: 40 + barColumn.index * 45
                        onTriggered: barSlot.grown = true
                    }

                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: barSlot.cap
                        topRightRadius: barSlot.cap
                        color: Theme.withAlpha(barSlot.barAccent, barSlot.hovered ? 0.1 : 0.05)
                        Behavior on color {
                            ColorAnimation {
                                duration: 160
                            }
                        }
                    }

                    Rectangle {
                        id: barFill
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: barSlot.grown ? Math.max(3, barSlot.ratio * parent.height) : 0
                        topLeftRadius: Math.min(barSlot.cap, height / 2)
                        topRightRadius: Math.min(barSlot.cap, height / 2)
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: Theme.withAlpha(barSlot.barAccent, barSlot.today || barSlot.hovered ? 1.0 : 0.72)
                            }
                            GradientStop {
                                position: 1.0
                                color: Theme.withAlpha(barSlot.barAccent, barSlot.today || barSlot.hovered ? 0.78 : 0.42)
                            }
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 520
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        // Baseline shared by every column.
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(barSlot.barAccent, 0.35)
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 4
                        y: barSlot.hovered ? 4 : 10
                        spacing: 0
                        opacity: barSlot.hovered ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                            }
                        }
                        Behavior on y {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: barColumn.modelData.primary || ""
                            color: Theme.surfaceText
                            style: Text.Outline
                            styleColor: Theme.withAlpha(Theme.surfaceContainer, 0.6)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: text.length > 0
                            text: barColumn.modelData.secondary || ""
                            color: Theme.surfaceText
                            style: Text.Outline
                            styleColor: Theme.withAlpha(Theme.surfaceContainer, 0.6)
                            font.pixelSize: Theme.fontSizeSmall - 1
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: dayHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }

                StyledText {
                    width: parent.width
                    text: barColumn.modelData.label || ""
                    horizontalAlignment: Text.AlignHCenter
                    color: barSlot.today ? Theme.warning : (barSlot.hovered ? Theme.surfaceText : Theme.surfaceVariantText)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: barSlot.today ? Font.Bold : Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
    }

    component AccountBlock: StyledRect {
        id: acct
        property var account
        readonly property real worst: root.accountWorstPercent(account)
        readonly property color accent: root.getUsageColor(worst)
        readonly property var windows: root.accountWindows(account)
        width: parent ? parent.width : implicitWidth
        implicitHeight: acctCol.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius + 2
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(accent, 0.28)

        Rectangle { // accent bar
            width: 3
            radius: 2
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
                margins: Theme.spacingS
            }
            color: acct.accent
        }

        Column {
            id: acctCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: Theme.spacingL + 5
                rightMargin: Theme.spacingM
                topMargin: Theme.spacingM
            }
            spacing: Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS
                DankIcon {
                    name: "deployed_code"
                    size: 16
                    color: acct.accent
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.accountLabel(acct.account)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: root.accountEmailFor(acct.account)
                        visible: text.length > 0
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 2
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
                StyledText {
                    text: `${Math.round(acct.worst)}%`
                    color: acct.accent
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            StyledText { // concise family explanation; detailed mode keeps model labels self-explanatory
                width: parent.width
                visible: !!acct.account && !!acct.account.groupDescription && !root.showAntigravityModelDetails
                text: root.t("card.antigravity_families", "Quota families shared by Antigravity")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 2
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: acct.windows
                delegate: UsageBar {
                    required property var modelData
                    width: parent.width
                    label: modelData.name || modelData.resetDescription || ""
                    percent: Number(modelData.usedPercent || 0)
                    aside: (modelData.description && String(modelData.description).length > 0) ? String(modelData.description) : `${Math.round(Number(modelData.usedPercent || 0))}% used`
                    accentColor: root.getUsageColor(Number(modelData.usedPercent || 0))
                }
            }
        }
    }

    component ProviderDashboardCard: StyledRect {
        id: card
        DropArea {
            anchors.fill: parent
            keys: ["application/x-aioc-provider"]
            onDropped: drop => {
                if (!root.isPinned(card.provider.provider))
                    return;
                const source = drop.getDataAsString("application/x-aioc-provider");
                if (root.isPinned(source)) {
                    root.movePinnedBefore(source, card.provider.provider);
                    drop.acceptProposedAction();
                }
            }
        }
        required property var provider
        property bool expanded: root.allExpanded || (!!provider && provider.provider === root.focusedProviderId)
        property bool hasUsage: !!provider && !!provider.usage && !provider.error
        property color accentColor: provider && provider.error ? Theme.error : root.providerAccent(provider ? provider.provider : "")
        property var windows: root.windowsForProvider(provider)
        property bool compact: width < 560
        property bool veryCompact: width < 430
        property bool dense: root.densityMode === "compact"
        property bool hovered: cardMouse.containsMouse
        readonly property bool isStale: {
            root.staleTickMs;
            const updated = root.providerUpdatedMs(provider);
            return updated > 0 && (Date.now() - updated) > root.refreshIntervalMs * 2;
        }

        function toggleExpanded() {
            if (root.allExpanded) {
                root.allExpanded = false;
                root.focusedProviderId = card.provider.provider;
                return;
            }
            root.focusedProviderId = card.expanded ? "" : card.provider.provider;
        }

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 4
        color: expanded ? Theme.surfaceContainerHigh : (hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer)
        border.width: 1
        border.color: {
            if (card.activeFocus)
                return Theme.primary;
            if (provider && provider.error)
                return Theme.withAlpha(Theme.error, expanded ? 0.34 : 0.16);
            if (root.hasPartialAccountErrors(provider))
                return Theme.withAlpha(Theme.warning, expanded ? 0.48 : 0.24);
            return Theme.withAlpha(accentColor, expanded ? 0.42 : (hovered ? 0.26 : 0.07));
        }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.providerName(provider ? provider.provider : "")
        Accessible.description: root.providerSubtitle(provider)
        Keys.onReturnPressed: toggleExpanded()
        Keys.onSpacePressed: toggleExpanded()
        Keys.onDeletePressed: {
            if (root.selectedProviders.length > 1)
                root.removeProvider(card.provider.provider);
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_P) {
                root.togglePin(card.provider.provider);
                event.accepted = true;
            } else if (event.key === Qt.Key_R && card.provider.error) {
                root.retryProvider(card.provider.provider);
                event.accepted = true;
            }
        }
        implicitHeight: cardColumn.implicitHeight + (card.dense ? Theme.spacingS : (card.compact ? Theme.spacingM : Theme.spacingL)) * 2
        clip: true
        // No hover scale on purpose: cards sit flush against the Flickable's
        // clip edge, so any scale-up gets chopped on the left. Hover feedback
        // stays on the background, border and gradient changes below.

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: expanded || hovered ? 1 : 0.32
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.withAlpha(card.accentColor, expanded ? 0.12 : 0.055)
                }
                GradientStop {
                    position: 0.52
                    color: Theme.withAlpha(card.accentColor, 0.025)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.withAlpha(Theme.surfaceContainer, 0.0)
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: expanded ? parent.height - Theme.spacingM * 2 : parent.height * 0.34
            radius: width / 2
            visible: expanded || card.hovered || card.activeFocus
            color: Theme.withAlpha(card.accentColor, expanded ? 0.95 : 0.55)
            // Height tracks the card's animated implicitHeight directly. An
            // extra Behavior here would stack on the card's own height
            // animation, making the bar lag and drift off-center while the
            // card expands or collapses.
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 180
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 180
            }
        }
        Behavior on implicitHeight {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: cardColumn
            z: 2
            anchors {
                fill: parent
                margins: card.dense ? Theme.spacingS : (card.compact ? Theme.spacingS : Theme.spacingM)
                // The left accent bar (4px inset + 3px wide) needs clearance
                // so the title block never visually hugs it on hover/expand.
                leftMargin: (card.dense ? Theme.spacingS : (card.compact ? Theme.spacingS : Theme.spacingM)) + Theme.spacingM
            }
            spacing: expanded ? (card.dense ? Theme.spacingS : Theme.spacingM) : Theme.spacingS

            RowLayout {
                width: parent.width
                spacing: card.compact ? Theme.spacingS : Theme.spacingL

                Item {
                    id: pinDrag
                    visible: root.isPinned(card.provider.provider)
                    implicitWidth: 20
                    implicitHeight: 28
                    Drag.mimeData: ({ "application/x-aioc-provider": card.provider.provider })
                    Drag.supportedActions: Qt.MoveAction
                    StyledText { anchors.centerIn: parent; text: "↕"; color: Theme.surfaceVariantText }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.OpenHandCursor
                        onPressAndHold: pinDrag.Drag.startDrag()
                    }
                    ToolTip.visible: pinHover.hovered
                    ToolTip.text: root.t("card.reorder_pinned", "Hold and drag to reorder pinned providers")
                    HoverHandler { id: pinHover }
                }
                Item {
                    Layout.alignment: Qt.AlignTop
                    visible: !card.veryCompact
                    width: card.dense ? 34 : (card.compact ? 38 : 46)
                    height: width

                    ProgressRing {
                        anchors.fill: parent
                        visible: card.hasUsage
                        percent: root.providerPercent(card.provider)
                        thickness: 2.5
                        accentColor: root.getUsageColor(root.providerPercent(card.provider))
                        trackColor: Theme.withAlpha(card.accentColor, 0.14)
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: width / 2
                        // Logo surfaces intentionally use the single
                        // user-selected provider-logo colour. Usage state
                        // remains on the surrounding progress ring instead
                        // of making each provider mark look like a different
                        // brand-coloured icon.
                        color: Theme.withAlpha(root.providerLogoColor, 0.14)
                        border.width: 1
                        border.color: Theme.withAlpha(root.providerLogoColor, 0.32)

                        ProviderLogo {
                            anchors.centerIn: parent
                            providerId: card.provider.provider
                            logoSize: card.dense ? 15 : (card.compact ? 17 : 20)
                            tintColor: root.providerLogoColor
                        }
                    }
                }

                Column {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: card.dense ? 3 : 6

                    StyledText {
                        width: parent.width
                        text: root.providerName(card.provider.provider)
                        color: Theme.surfaceText
                        font.pixelSize: card.dense ? Theme.fontSizeSmall : (card.compact ? Theme.fontSizeSmall + 1 : Theme.fontSizeMedium)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: root.providerSubtitle(card.provider)
                        color: card.provider.error ? Theme.withAlpha(Theme.error, 0.92) : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        maximumLineCount: card.provider.error ? (expanded ? 3 : 2) : (expanded ? 2 : 1)
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS

                        BadgePill {
                            label: root.providerSourceLabel(card.provider)
                            iconName: "sync_alt"
                            accentColor: Theme.primary
                        }

                        BadgePill {
                            // Distinguishes non-provider entries (agent
                            // analytics, gateways, self-hosted inference) so
                            // local tooling never reads as one more cloud API.
                            visible: !root.isPlainProvider(card.provider.provider)
                            label: root.providerKindsLabel(card.provider.provider)
                            iconName: root.providerKindIconFor(card.provider.provider)
                            accentColor: root.providerKindAccentFor(card.provider.provider)
                        }

                        BadgePill {
                            label: root.providerStatusLabel(card.provider)
                            iconName: card.provider && card.provider.error ? "warning" : "check_circle"
                            accentColor: card.provider && card.provider.error ? Theme.warning : root.providerAccent(card.provider.provider)
                        }

                        BadgePill {
                            visible: card.isStale
                            label: root.t("status.stale", "Stale")
                            iconName: "schedule"
                            accentColor: Theme.warning
                            emphasized: true
                        }

                        BadgePill {
                            visible: !!card.provider.error
                            label: root.retryingProviderId === card.provider.provider ? "…" : root.t("card.retry", "Retry")
                            iconName: "refresh"
                            accentColor: Theme.error
                            emphasized: true
                            onTapped: root.retryProvider(card.provider.provider)
                        }
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 3

                    DankIcon {
                        readonly property string trend: root.providerTrend(card.provider ? card.provider.provider : "")
                        visible: !card.provider.error && trend.length > 0 && trend !== "flat"
                        name: trend === "up" ? "trending_up" : "trending_down"
                        size: card.compact ? 15 : 17
                        color: trend === "up" ? Theme.warning : Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: card.provider.error ? t("status.error", "Error") : `${Math.round(root.providerPercent(card.provider))}%`
                        color: card.provider.error ? Theme.error : root.getUsageColor(root.providerPercent(card.provider))
                        font.pixelSize: card.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Card actions share the popout header's capsule language.
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    z: 2
                    spacing: 2

                    HeaderAction {
                        width: card.compact ? 30 : 34
                        height: width
                        position: "first"
                        iconName: "star"
                        active: root.isPinned(card.provider.provider)
                        label: root.t("card.pin", "Pin")
                        onTriggered: root.togglePin(card.provider.provider)
                    }

                    HeaderAction {
                        visible: root.selectedProviders.length > 1
                        width: card.compact ? 30 : 34
                        height: width
                        iconName: "close"
                        accent: Theme.error
                        hoverRotation: 90
                        label: root.t("header.close", "Close")
                        onTriggered: root.removeProvider(card.provider.provider)
                    }

                    HeaderAction {
                        width: card.compact ? 30 : 34
                        height: width
                        position: "last"
                        iconName: "keyboard_arrow_down"
                        accent: card.accentColor
                        active: card.expanded
                        iconRotation: card.expanded ? 180 : 0
                        label: root.t("card.expand", "Details")
                        onTriggered: {
                            card.forceActiveFocus();
                            card.toggleExpanded();
                        }
                    }
                }
            }

            UsageBar {
                visible: card.hasUsage && !card.expanded && !card.dense
                width: parent.width
                label: card.windows.length > 0 ? card.windows[0].label : t("status.usage", "Usage")
                percent: root.providerPercent(card.provider)
                aside: card.windows.length > 0 ? root.formatUsageLine(card.windows[0].data) : `${Math.round(root.providerPercent(card.provider))}%`
                accentColor: root.getUsageColor(root.providerPercent(card.provider))
            }

            Column {
                visible: card.expanded
                width: parent.width
                spacing: Theme.spacingL

                RowLayout {
                    visible: root.hasPartialAccountErrors(card.provider)
                    width: parent.width
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "warning"
                        size: 17
                        color: Theme.warning
                        Layout.alignment: Qt.AlignTop
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.partialAccountErrorText(card.provider)
                        color: Theme.warning
                        font.pixelSize: Theme.fontSizeSmall - 1
                        wrapMode: Text.WordWrap
                    }
                }

                Repeater {
                    model: (card.expanded && !root.hasMultipleAccounts(card.provider)) ? card.windows : []

                    UsageBar {
                        required property var modelData
                        width: parent.width
                        label: modelData.label
                        percent: Number(modelData.data.usedPercent || 0)
                        aside: root.formatUsageLine(modelData.data)
                        accentColor: root.getUsageColor(Number(modelData.data.usedPercent || 0))
                    }
                }

                Column { // multi-account breakdown (Antigravity: one block per IDE / Google account)
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.hasMultipleAccounts(card.provider)

                    Repeater {
                        model: (card.expanded && root.hasMultipleAccounts(card.provider)) ? root.accountsForProvider(card.provider) : []

                        delegate: AccountBlock {
                            required property var modelData
                            width: parent.width
                            account: modelData
                        }
                    }
                }

                Column {
                    readonly property var historyPoints: root.usageHistory[card.provider.provider] || []
                    visible: card.hasUsage && historyPoints.length >= 2
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: t("card.history", "History")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: Font.Medium
                    }

                    Sparkline {
                        width: parent.width
                        height: 38
                        points: parent.historyPoints
                        lineColor: root.getUsageColor(root.providerPercent(card.provider))
                    }
                }

                Flow {
                    visible: card.hasUsage
                    width: parent.width
                    spacing: Theme.spacingXS

                    InfoPill {
                        iconName: "person"
                        label: card.provider.provider === "antigravity" && root.accountsForProvider(card.provider).length >= 2 ? t("card.accounts", "Accounts") : t("card.account", "Account")
                        value: root.providerAccount(card.provider)
                        accentColor: card.accentColor
                    }

                    InfoPill {
                        iconName: "vpn_key"
                        label: t("card.login", "Login")
                        value: root.providerLogin(card.provider)
                        accentColor: card.accentColor
                    }

                    InfoPill {
                        visible: root.providerCredits(card.provider) !== "—"
                        iconName: "toll"
                        label: t("card.credits", "Credits")
                        value: root.providerCredits(card.provider)
                        accentColor: card.accentColor
                    }
                }

                SurfaceButton {
                    visible: root.providerConsoleUrl(card.provider.provider, card.provider.source).length > 0
                    iconName: "open_in_new"
                    label: t("card.open_console", "Open console")
                    compact: true
                    onTriggered: root.openProviderConsole(card.provider.provider, card.provider.source)
                }

                StyledRect {
                    visible: card.provider.provider === "claude"
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.warning, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.warning, 0.22)
                    implicitHeight: claudeCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: claudeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.claude_details", "Claude Code details")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            BadgePill {
                                visible: root.claudeExtraUsageEnabled
                                label: t("card.extra_usage_on", "Extra usage on")
                                iconName: "add_circle"
                                accentColor: Theme.warning
                            }

                            StyledText {
                                text: root.formatTier(root.claudeRateLimitTier)
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        UsageBar {
                            width: parent.width
                            label: t("window.weekly", "Weekly")
                            percent: root.claudeSevenDayUtil
                            aside: {
                                const reset = root.formatTimeUntil(root.claudeSevenDayReset);
                                return reset.length > 0 ? `${Math.round(root.claudeSevenDayUtil)}% · ${reset}` : `${Math.round(root.claudeSevenDayUtil)}%`;
                            }
                            accentColor: root.getUsageColor(root.claudeSevenDayUtil)
                        }

                        UsageBar {
                            width: parent.width
                            visible: root.claudeScopedLimitModel !== "" && root.claudeScopedLimitUtil > 0
                            label: `${t("window.weekly", "Weekly")} · ${root.claudeScopedLimitModel}`
                            percent: root.claudeScopedLimitUtil
                            aside: {
                                const reset = root.formatTimeUntil(root.claudeScopedLimitReset);
                                return reset.length > 0 ? `${Math.round(root.claudeScopedLimitUtil)}% · ${reset}` : `${Math.round(root.claudeScopedLimitUtil)}%`;
                            }
                            accentColor: root.getUsageColor(root.claudeScopedLimitUtil)
                        }

                        Row {
                            visible: !!root.claudeWeekBurnForecast && root.claudeWeekBurnForecast.exceed
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "local_fire_department"
                                size: 14
                                color: Theme.error
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.claudeWeekBurnForecast ? root.claudeWeekBurnForecast.text : ""
                                color: Theme.error
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        UsageBar {
                            width: parent.width
                            label: root.t("window.session", "Session")
                            percent: root.claudeFiveHourUtil
                            aside: {
                                const reset = root.formatTimeUntil(root.claudeFiveHourReset);
                                return reset.length > 0 ? `${Math.round(root.claudeFiveHourUtil)}% · ${reset}` : `${Math.round(root.claudeFiveHourUtil)}%`;
                            }
                            accentColor: root.getUsageColor(root.claudeFiveHourUtil)
                        }

                        Row {
                            visible: !!root.claudeBurnForecast
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? "local_fire_department" : "check_circle"
                                size: 14
                                color: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Theme.error : Theme.success
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.claudeBurnForecast ? root.claudeBurnForecast.text : ""
                                color: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Theme.error : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: root.claudeBurnForecast && root.claudeBurnForecast.exceed ? Font.DemiBold : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : (card.width < 760 ? 2 : 4)
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.today_tokens", "Today tokens")
                                value: root.formatTokens(root.claudeDailyTokens[root.currentWeekdayIndex] || 0)
                                accentColor: Theme.warning
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.today_cost", "Today cost")
                                value: root.formatCost(root.claudeTodayCost)
                                accentColor: Theme.warning
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.week", "Week")
                                value: `${root.formatTokens(root.claudeWeekTokens)} · ${root.formatCost(root.claudeWeekCost)}`
                                accentColor: Theme.warning
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.month", "Month")
                                value: `${root.formatTokens(root.claudeMonthTokens)} · ${root.formatCost(root.claudeMonthCost)}`
                                accentColor: Theme.warning
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                visible: root.claudeMonthProjection > 0
                                label: t("card.projected_month", "Projected month")
                                value: `≈ ${root.formatCost(root.claudeMonthProjection)}`
                                accentColor: root.claudeMonthProjection > root.claudeMonthCost * 1.5 ? Theme.error : Theme.warning
                            }
                        }

                        ClaudeDailyBars {
                            width: parent.width
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.models_week", "Models this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: claudeModelList

                                UsageBar {
                                    required property string modelName
                                    required property real modelTokens
                                    required property real modelCost
                                    width: parent.width
                                    label: modelName
                                    percent: root.claudeWeekTokens > 0 ? (modelTokens / root.claudeWeekTokens) * 100 : 0
                                    aside: modelCost > 0 ? `${root.formatTokens(modelTokens)} · ${root.formatCost(modelCost)}` : root.formatTokens(modelTokens)
                                    accentColor: Theme.warning
                                }
                            }
                        }

                        Column {
                            visible: root.showClaudeProjects && claudeProjectList.count > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.top_projects", "Top projects this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: claudeProjectList

                                Column {
                                    required property string projectPath
                                    required property real projectTokens
                                    required property int index
                                    width: parent.width
                                    spacing: 3

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: root.projectDisplayName(projectPath)
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.compactPath(projectPath)
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            elide: Text.ElideLeft
                                        }

                                        StyledText {
                                            text: root.formatTokens(projectTokens)
                                            color: Theme.warning
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5
                                        radius: 2.5
                                        color: Theme.withAlpha(Theme.surfaceText, 0.06)

                                        Rectangle {
                                            readonly property real topTokens: claudeProjectList.count > 0 ? Math.max(1, claudeProjectList.get(0).projectTokens) : 1
                                            width: Math.max(3, (projectTokens / topTokens) * parent.width)
                                            height: parent.height
                                            radius: parent.radius
                                            color: Theme.withAlpha(Theme.warning, index === 0 ? 0.85 : 0.45)

                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: t("card.claude_since", "Since {date} · {sessions} sessions · {messages} messages", {
                                date: root.claudeFirstSession || "—",
                                sessions: root.claudeAlltimeSessions,
                                messages: root.claudeAlltimeMessages
                            })
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            elide: Text.ElideRight
                        }
                    }
                }

                StyledRect {
                    visible: card.provider.provider === "9router" && root.nineStats !== null
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.secondary, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.secondary, 0.22)
                    implicitHeight: nineCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: nineCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        readonly property var stats: root.nineStats || ({})
                        readonly property var nineToday: stats.today || ({})
                        readonly property var nineWeek: stats.week || ({})
                        readonly property var nineMonth: stats.month || ({})
                        readonly property var nineDays: stats.days || []
                        readonly property var nineModels: stats.topModels || []
                        readonly property var nineProviders: stats.byProvider || []

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.nine_details", "9Router telemetry")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: t("card.nine_month_total", "{cost} this month", {
                                    cost: root.formatCost(Number(nineCol.nineMonth.cost || 0))
                                })
                                color: Theme.secondary
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : (card.width < 760 ? 2 : 4)
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.nine_today", "Today")
                                value: `${root.formatCost(Number(nineCol.nineToday.cost || 0))} · ${Number(nineCol.nineToday.requests || 0)} ${root.t("unit.req", "req")}`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.week", "Week")
                                value: `${root.formatCost(Number(nineCol.nineWeek.cost || 0))} · ${Number(nineCol.nineWeek.requests || 0)} ${root.t("unit.req", "req")}`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.month", "Month")
                                value: `${root.formatCost(Number(nineCol.nineMonth.cost || 0))} · ${Number(nineCol.nineMonth.requests || 0)} ${root.t("unit.req", "req")}`
                                accentColor: Theme.secondary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.nine_week_tokens", "Week tokens")
                                value: root.t("card.nine_io", "{input} in · {cached} cached · {output} out", { input: root.formatTokens(Number(nineCol.nineWeek.promptTokens || 0)), cached: root.formatTokens(Number(nineCol.nineWeek.cachedTokens || 0)), output: root.formatTokens(Number(nineCol.nineWeek.completionTokens || 0)) })
                                accentColor: Theme.secondary
                            }
                        }

                        // 7-day cost chart, calendar aligned (today is the last bar).
                        DailyBarChart {
                            width: parent.width
                            accent: Theme.secondary
                            bars: nineCol.nineDays.map((day, i) => ({
                                        value: Number(day.cost || 0),
                                        primary: root.formatCost(Number(day.cost || 0)),
                                        secondary: `${Number(day.requests || 0)} ${root.t("unit.req", "req")}`,
                                        label: root.weekdayLabel(day),
                                        today: i === nineCol.nineDays.length - 1
                                    }))
                        }

                        Column {
                            visible: nineCol.nineModels.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.nine_models_week", "Top models (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: nineCol.nineModels

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: modelData.provider ? `${modelData.model} · ${modelData.provider}` : String(modelData.model || "")
                                    percent: Number(nineCol.nineWeek.cost || 0) > 0 ? (Number(modelData.cost || 0) / Number(nineCol.nineWeek.cost)) * 100 : 0
                                    aside: `${root.formatCost(Number(modelData.cost || 0))} · ${Number(modelData.requests || 0)} ${root.t("unit.req", "req")}`
                                    accentColor: Theme.secondary
                                }
                            }
                        }

                        Column {
                            visible: nineCol.nineProviders.length > 1
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.nine_providers_week", "Routed providers (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: nineCol.nineProviders

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: root.providerName(String(modelData.provider || ""))
                                    percent: Number(nineCol.nineWeek.cost || 0) > 0 ? (Number(modelData.cost || 0) / Number(nineCol.nineWeek.cost)) * 100 : 0
                                    aside: `${root.formatCost(Number(modelData.cost || 0))} · ${Number(modelData.requests || 0)} ${root.t("unit.req", "req")}`
                                    accentColor: Theme.secondary
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    visible: (card.provider.provider === "pi" && root.piStats !== null) || (card.provider.provider === "codex" && root.codexStats !== null) || (card.provider.provider === "opencode" && root.opencodeStats !== null)
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.success, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.success, 0.22)
                    implicitHeight: piCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: piCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        readonly property var stats: (card.provider.provider === "codex" ? root.codexStats : card.provider.provider === "opencode" ? root.opencodeStats : root.piStats) || ({})
                        readonly property var piToday: stats.today || ({})
                        readonly property var piWeek: stats.week || ({})
                        readonly property var piMonth: stats.month || ({})
                        readonly property var piDays: stats.days || []
                        readonly property var piModels: stats.topModels || []
                        readonly property var piProjects: stats.topProjects || []

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: card.provider.provider === "pi" ? t("card.pi_details", "pi telemetry") : root.providerName(card.provider.provider) + " · " + t("card.local_telemetry", "Local telemetry")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: t("card.pi_month_total", "{cost} this month", {
                                    cost: root.formatCost(piCol.piMonth.cost)
                                })
                                color: Theme.success
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.pi_today", "Today")
                                value: `${root.formatCost(piCol.piToday.cost)} · ${root.formatTokens(Number(piCol.piToday.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.week", "Week")
                                value: `${root.formatCost(piCol.piWeek.cost)} · ${root.formatTokens(Number(piCol.piWeek.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.month", "Month")
                                value: `${root.formatCost(piCol.piMonth.cost)} · ${root.formatTokens(Number(piCol.piMonth.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.success
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: t("card.local_cost_note", "Local costs may be estimates, not invoices. — means unavailable or incomplete; $0 is not proof of free usage.")
                            wrapMode: Text.WordWrap
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        GridLayout {
                            width: parent.width
                            columns: 3
                            visible: card.provider.provider !== "pi"
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_input", "Input (7d)")
                                value: root.formatTokens(piCol.piWeek.input)
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_output", "Output (7d)")
                                value: root.formatTokens(piCol.piWeek.output)
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_cache", "Cache read (7d)")
                                value: root.formatTokens(piCol.piWeek.cacheRead)
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_reasoning", "Reasoning (7d)")
                                value: root.formatTokens(piCol.piWeek.reasoning)
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_calls", "Usage events (7d)")
                                value: String(piCol.piWeek.calls || 0)
                                accentColor: Theme.success
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.local_sessions", "Sessions (7d)")
                                value: String(piCol.piWeek.sessions || 0)
                                accentColor: Theme.success
                            }
                        }
                        // Token activity remains useful when no cost is available.
                        DailyBarChart {
                            width: parent.width
                            accent: Theme.success
                            bars: piCol.piDays.map((day, i) => ({
                                        value: Number(day.tokens || 0),
                                        primary: root.formatCost(day.cost),
                                        secondary: root.formatTokens(Number(day.tokens || 0)),
                                        label: root.weekdayLabel(day),
                                        today: i === piCol.piDays.length - 1
                                    }))
                        }

                        Column {
                            visible: piCol.piModels.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.pi_models_week", "Top models (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: piCol.piModels

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: String(modelData.model || "")
                                    percent: Number(piCol.piWeek.cost || 0) > 0 ? (Number(modelData.cost || 0) / Number(piCol.piWeek.cost)) * 100 : 0
                                    aside: `${root.formatCost(modelData.cost)} · ${root.formatTokens(Number(modelData.tokens || 0))}`
                                    accentColor: Theme.success
                                }
                            }
                        }

                        Column {
                            visible: piCol.piProjects.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.top_projects", "Top projects this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: piCol.piProjects

                                Column {
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    spacing: 3

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: root.projectDisplayName(String(modelData.cwd || ""))
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.compactPath(String(modelData.cwd || ""))
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            elide: Text.ElideLeft
                                        }

                                        StyledText {
                                            text: root.formatTokens(Number(modelData.tokens || 0))
                                            color: Theme.success
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5
                                        radius: 2.5
                                        color: Theme.withAlpha(Theme.surfaceText, 0.06)

                                        Rectangle {
                                            readonly property real topTokens: piCol.piProjects.length > 0 ? Math.max(1, Number(piCol.piProjects[0].tokens || 0)) : 1
                                            width: Math.max(3, (Number(modelData.tokens || 0) / topTokens) * parent.width)
                                            height: parent.height
                                            radius: parent.radius
                                            color: Theme.withAlpha(Theme.success, index === 0 ? 0.85 : 0.45)

                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    visible: card.provider.provider === "hermes" && root.hermesStats !== null
                    width: parent.width
                    radius: Theme.cornerRadius + 2
                    color: Theme.withAlpha(Theme.primary, 0.08)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.22)
                    implicitHeight: hermesCol.implicitHeight + Theme.spacingL * 2

                    Column {
                        id: hermesCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingL

                        StyledText {
                            width: parent.width
                            text: t("card.local_cost_note", "Local costs may be estimates, not invoices. — means unavailable or incomplete; $0 is not proof of free usage.")
                            wrapMode: Text.WordWrap
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        readonly property var stats: root.hermesStats || ({})
                        readonly property var meta: stats.meta || ({})
                        readonly property var hToday: stats.today || ({})
                        readonly property var hWeek: stats.week || ({})
                        readonly property var hMonth: stats.month || ({})
                        readonly property var hDays: stats.days || []
                        readonly property var hModels: stats.topModels || []
                        readonly property var hProjects: stats.topProjects || []
                        readonly property var hSources: meta.sources || []

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                Layout.fillWidth: true
                                text: t("card.hermes_details", "Hermes telemetry")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                            }

                            StyledText {
                                text: t("card.hermes_month_total", "{cost} this month", {
                                    cost: root.formatCost(hermesCol.hMonth.cost)
                                })
                                color: Theme.primary
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }
                        }

                        // Identity row: the two natures of Hermes — the agent
                        // harness (default model) and the provider it routes
                        // through (active billing provider).
                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS

                            InfoPill {
                                visible: String(hermesCol.meta.defaultModel || "").length > 0
                                label: t("card.hermes_default_model", "Model")
                                value: String(hermesCol.meta.defaultModel || "")
                                iconName: "tune"
                                accentColor: Theme.primary
                            }
                            InfoPill {
                                visible: String(hermesCol.meta.activeProvider || "").length > 0
                                label: t("card.hermes_active_provider", "Billing")
                                value: String(hermesCol.meta.activeProvider || "")
                                iconName: "account_balance"
                                accentColor: Theme.secondary
                            }
                            InfoPill {
                                label: t("card.hermes_sessions", "Sessions")
                                value: String(hermesCol.meta.sessions || 0)
                                iconName: "forum"
                                accentColor: Theme.surfaceVariantText
                            }
                            InfoPill {
                                label: t("card.hermes_messages", "Messages")
                                value: String(hermesCol.meta.messages || 0)
                                iconName: "chat"
                                accentColor: Theme.surfaceVariantText
                            }
                            InfoPill {
                                visible: Number(hermesCol.hWeek.calls || 0) > 0
                                label: t("card.hermes_api_calls", "API calls (7d)")
                                value: String(hermesCol.hWeek.calls || 0)
                                iconName: "api"
                                accentColor: Theme.surfaceVariantText
                            }
                        }

                        StyledText {
                            visible: String(hermesCol.meta.version || "").length > 0
                            width: parent.width
                            text: String(hermesCol.meta.version || "")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall - 1
                            elide: Text.ElideRight
                        }

                        GridLayout {
                            width: parent.width
                            columns: card.width < 520 ? 1 : 3
                            columnSpacing: Theme.spacingM
                            rowSpacing: Theme.spacingM

                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.hermes_today", "Today")
                                value: `${root.formatCost(hermesCol.hToday.cost)} · ${root.formatTokens(Number(hermesCol.hToday.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.primary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.week", "Week")
                                value: `${root.formatCost(hermesCol.hWeek.cost)} · ${root.formatTokens(Number(hermesCol.hWeek.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.primary
                            }
                            MetricTile {
                                Layout.fillWidth: true
                                label: t("card.month", "Month")
                                value: `${root.formatCost(hermesCol.hMonth.cost)} · ${root.formatTokens(Number(hermesCol.hMonth.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                accentColor: Theme.primary
                            }
                        }

                        // 7-day token chart, trailing window (today is the last
                        // bar). Hermes costs are often unpriced locally, so the
                        // bars carry tokens; hover still shows both.
                        DailyBarChart {
                            width: parent.width
                            accent: Theme.primary
                            bars: hermesCol.hDays.map((day, i) => ({
                                        value: Number(day.tokens || 0),
                                        primary: root.formatTokens(Number(day.tokens || 0)),
                                        secondary: root.formatCost(day.cost),
                                        label: root.weekdayLabel(day),
                                        today: i === hermesCol.hDays.length - 1
                                    }))
                        }

                        Column {
                            visible: hermesCol.hModels.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.hermes_models_week", "Top models (7 days)")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: hermesCol.hModels

                                UsageBar {
                                    required property var modelData
                                    width: parent.width
                                    label: String(modelData.model || "")
                                    percent: Number(hermesCol.hWeek.tokens || 0) > 0 ? (Number(modelData.tokens || 0) / Number(hermesCol.hWeek.tokens)) * 100 : 0
                                    aside: `${root.formatTokens(Number(modelData.tokens || 0))} ${root.t("unit.tok", "tok")} · ${root.formatCost(modelData.cost)}`
                                    accentColor: Theme.primary
                                }
                            }
                        }

                        Column {
                            visible: hermesCol.hProjects.length > 0
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                width: parent.width
                                text: t("card.top_projects", "Top projects this week")
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: hermesCol.hProjects

                                Column {
                                    required property var modelData
                                    required property int index
                                    width: parent.width
                                    spacing: 3

                                    RowLayout {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: root.projectDisplayName(String(modelData.cwd || ""))
                                            color: Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.DemiBold
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.compactPath(String(modelData.cwd || ""))
                                            color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                            elide: Text.ElideLeft
                                        }

                                        StyledText {
                                            text: `${root.formatTokens(Number(modelData.tokens || 0))} ${root.t("unit.tok", "tok")}`
                                            color: Theme.surfaceVariantText
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5
                                        radius: 2.5
                                        color: Theme.withAlpha(Theme.surfaceText, 0.06)

                                        Rectangle {
                                            readonly property real topTokens: hermesCol.hProjects.length > 0 ? Math.max(1, Number(hermesCol.hProjects[0].tokens || 0)) : 1
                                            width: Math.max(3, (Number(modelData.tokens || 0) / topTokens) * parent.width)
                                            height: parent.height
                                            radius: parent.radius
                                            color: Theme.withAlpha(Theme.primary, index === 0 ? 0.85 : 0.45)

                                            Behavior on width {
                                                NumberAnimation {
                                                    duration: 300
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Flow {
                            visible: hermesCol.hSources.length > 0
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledText {
                                text: t("card.hermes_sources", "Session sources") + ":"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall - 1
                                font.weight: Font.DemiBold
                                // Flow positions its children itself and disables
                                // itself entirely if one of them uses anchors, so
                                // the label is centred against the BadgePill row
                                // height instead.
                                height: 28
                                verticalAlignment: Text.AlignVCenter
                            }

                            Repeater {
                                model: hermesCol.hSources

                                BadgePill {
                                    required property var modelData
                                    label: `${String(modelData.source || "?")} · ${modelData.sessions}`
                                    iconName: "forum"
                                    accentColor: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }
            }

            Row {
                visible: card.hasUsage && root.lastUpdated.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                DankIcon {
                    name: card.isStale ? "schedule" : "check"
                    size: 12
                    color: card.isStale ? Theme.warning : Theme.withAlpha(Theme.surfaceVariantText, 0.6)
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.t("card.updated_at", "Updated {time}", {
                        time: root.providerUpdatedLabel(card.provider)
                    })
                    color: card.isStale ? Theme.withAlpha(Theme.warning, 0.8) : Theme.withAlpha(Theme.surfaceVariantText, 0.6)
                    font.pixelSize: Theme.fontSizeSmall - 2
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        MouseArea {
            id: cardMouse
            z: 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: card.dense ? 64 : (card.compact ? 76 : 82)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                card.forceActiveFocus();
                card.toggleExpanded();
            }
        }
    }

    component ProviderManager: StyledRect {
        id: manager

        width: parent ? parent.width : implicitWidth
        radius: Theme.cornerRadius + 4
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.2)
        implicitHeight: managerColumn.implicitHeight + Theme.spacingL * 2

        Column {
            id: managerColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            GridLayout {
                width: parent.width
                columns: width < 560 ? 1 : 3
                columnSpacing: Theme.spacingM
                rowSpacing: Theme.spacingM

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 34
                        height: 34
                        radius: 11
                        color: Theme.withAlpha(Theme.primary, 0.12)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.primary, 0.2)

                        DankIcon {
                            anchors.centerIn: parent
                            name: "playlist_add_check"
                            size: 16
                            color: Theme.primary
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        StyledText {
                            width: parent.width
                            text: t("card.provider_control", "Provider control")
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: root.selectedProviders.join(", ")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                DankDropdown {
                    id: addProviderDropdown
                    Layout.preferredWidth: 220
                    Layout.minimumWidth: 220
                    Layout.maximumWidth: 220
                    // DankDropdown's labelled mode binds its width to the
                    // parent. Inside this GridLayout that makes its trigger
                    // spill into adjacent cells and leaves the visible picker
                    // without a reliable hit target. Compact mode owns its
                    // explicit width, so the whole visible control is
                    // clickable at every dashboard width.
                    text: ""
                    description: ""
                    currentValue: root.pendingProviderId
                    options: root.availableProviderOptions
                    // Kind icons keep hosted providers visually separate from
                    // local tooling (gateway / agent analytics / self-hosted).
                    optionIcons: root.availableProviderOptions.map(function (id) {
                        return root.providerKindIconFor(id);
                    })
                    dropdownWidth: 220
                    enableFuzzySearch: true
                    onValueChanged: function (value) {
                        root.pendingProviderId = value;
                    }
                }

                SurfaceButton {
                    id: addProviderButton
                    Layout.fillWidth: managerColumn.width < 560
                    iconName: "add"
                    label: t("card.add_provider", "Add provider")
                    compact: true
                    prominent: true
                    actionEnabled: root.selectedProviders.indexOf(root.pendingProviderId) < 0
                    onTriggered: root.addProvider(root.pendingProviderId)
                }
            }
        }
    }
}

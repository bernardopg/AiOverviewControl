import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Standalone settings window opened from the popout header. It hosts the
// very same AiOverviewControlSettings the DMS Settings > Plugins page loads,
// bound to the shared PluginService, so both entry points read and write the
// same pluginData and never drift apart.
FloatingWindow {
    id: win

    property string pluginVersion: ""
    // Label of the header action under the cursor, shown in the subtitle.
    property string hoveredAction: ""

    readonly property string repoUrl: "https://github.com/bernardopg/AiOverviewControl"
    readonly property string registryUrl: "https://github.com/AvengeMedia/dms-plugin-registry/issues/358"
    // Right-hand gutter shared by header and body. The scrollbar lives in it,
    // so content never runs under the bar, and both edges line up with the
    // window's left margin.
    readonly property real gutter: Theme.spacingL - 4

    function t(key, fallback, params) {
        return AiOverviewControlI18n.tr(key, fallback, params);
    }

    function activate() {
        visible = true;
        settingsFlick.contentY = 0;
    }

    function showAbout() {
        visible = true;
        aboutWindow.visible = true;
    }

    title: t("header.settings", "Plugin settings") + " · AiOverviewControl"
    implicitWidth: 780
    implicitHeight: 820
    minimumSize: Qt.size(540, 480)
    color: Theme.surfaceContainer
    visible: false
    onVisibleChanged: if (!visible) win.aboutWindow.visible = false

    component BrandMark: Rectangle {
        property real markSize: 44
        width: markSize
        height: markSize
        radius: width / 2
        color: Theme.withAlpha(Theme.primary, 0.16)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.28)

        Image {
            anchors.centerIn: parent
            width: parent.width * 0.68
            height: width
            source: Qt.resolvedUrl("assets/logo.png")
            sourceSize: Qt.size(width * 2, width * 2)
            fillMode: Image.PreserveAspectFit
            mipmap: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: Theme.primary
            }
        }
    }

    component AboutLink: Rectangle {
        id: link
        required property string iconName
        required property string label
        required property string url
        property color accent: Theme.primary

        Layout.fillWidth: true
        implicitHeight: 44
        radius: Theme.cornerRadius
        color: linkMouse.containsMouse ? Theme.withAlpha(accent, 0.14) : Theme.withAlpha(Theme.surfaceText, 0.04)
        border.width: 1
        border.color: Theme.withAlpha(linkMouse.containsMouse ? accent : Theme.surfaceText, linkMouse.containsMouse ? 0.32 : 0.08)
        Behavior on color { ColorAnimation { duration: 160 } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            DankIcon {
                name: link.iconName
                size: 18
                color: link.accent
            }

            StyledText {
                Layout.fillWidth: true
                text: link.label
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall + 1
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            DankIcon {
                name: "open_in_new"
                size: 15
                color: linkMouse.containsMouse ? link.accent : Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(link.url)
        }
    }

    component VersionPill: Rectangle {
        visible: win.pluginVersion.length > 0
        implicitWidth: versionText.implicitWidth + Theme.spacingS * 2
        implicitHeight: 20
        radius: 10
        color: Theme.withAlpha(Theme.primary, 0.12)
        border.width: 1
        border.color: Theme.withAlpha(Theme.primary, 0.24)

        StyledText {
            id: versionText
            anchors.centerIn: parent
            text: "v" + win.pluginVersion
            color: Theme.primary
            font.pixelSize: Theme.fontSizeSmall - 2
            font.weight: Font.DemiBold
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        anchors.rightMargin: 4

        // Same brand card as the popout header.
        StyledRect {
            id: windowHeader
            width: parent.width - win.gutter
            height: 68
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
                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.12) }
                    GradientStop { position: 0.6; color: Theme.withAlpha(Theme.primary, 0.02) }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingM

                BrandMark {
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    RowLayout {
                        spacing: Theme.spacingS

                        StyledText {
                            text: win.t("app.title", "AI Usage Control")
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        VersionPill {
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: win.hoveredAction.length > 0 ? win.hoveredAction : win.t("header.settings", "Plugin settings")
                        color: win.hoveredAction.length > 0 ? Theme.primary : Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        elide: Text.ElideRight
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    HeaderAction {
                        position: "first"
                        iconName: "favorite"
                        accent: Theme.error
                        label: win.t("header.upvote", "Upvote on the DankLinux plugin registry")
                        onHoveredChanged: win.hoveredAction = hovered ? label : ""
                        onTriggered: Qt.openUrlExternally(win.registryUrl)
                    }

                    HeaderAction {
                        iconName: "code"
                        label: win.t("header.repo", "Source code on GitHub")
                        onHoveredChanged: win.hoveredAction = hovered ? label : ""
                        onTriggered: Qt.openUrlExternally(win.repoUrl)
                    }

                    HeaderAction {
                        iconName: "bug_report"
                        accent: Theme.warning
                        label: win.t("header.issues", "Report a bug or request a feature")
                        onHoveredChanged: win.hoveredAction = hovered ? label : ""
                        onTriggered: Qt.openUrlExternally(win.repoUrl + "/issues/new/choose")
                    }

                    HeaderAction {
                        position: "last"
                        iconName: "info"
                        active: win.aboutWindow.visible
                        label: win.t("header.about", "About AiOverviewControl")
                        onHoveredChanged: win.hoveredAction = hovered ? label : ""
                        onTriggered: win.aboutWindow.visible = !win.aboutWindow.visible
                    }
                }

                HeaderAction {
                    Layout.alignment: Qt.AlignVCenter
                    position: "single"
                    iconName: "close"
                    accent: Theme.error
                    hoverRotation: 90
                    label: win.t("header.close", "Close")
                    onHoveredChanged: win.hoveredAction = hovered ? label : ""
                    onTriggered: win.visible = false
                }
            }
        }

        Flickable {
            id: settingsFlick
            anchors.top: windowHeader.bottom
            anchors.topMargin: Theme.spacingM
            // DankToggle rows bleed spacingM left to align their text; widen
            // the clip by the same amount so their hover shape keeps its
            // rounded left edge. The Loader offset keeps content in place.
            anchors.left: parent.left
            anchors.leftMargin: -Theme.spacingM
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentWidth: width
            contentHeight: settingsPage.implicitHeight + Theme.spacingL
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                id: settingsScroll
                policy: ScrollBar.AsNeeded
                width: 10
                padding: 2
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: width / 2
                    color: Theme.withAlpha(Theme.surfaceText, settingsScroll.pressed ? 0.5 : (settingsScroll.hovered ? 0.34 : 0.2))
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }

            Loader {
                id: settingsPage
                // URL loading also works with an already-cached plugin qmldir.
                x: Theme.spacingM
                width: settingsFlick.width - Theme.spacingM - win.gutter
                Component.onCompleted: setSource(Qt.resolvedUrl("AiOverviewControlSettings.qml"), {
                    pluginService: PluginService,
                    showBrand: false
                })
            }
        }
    }

    // Held as a property, not a visual child: a window declared inside the
    // settings window's content would be parented to its item tree.
    property FloatingWindow aboutWindow: FloatingWindow {
        // Transient child: the compositor keeps it above the settings window.
        parentWindow: win
        title: win.t("header.about", "About AiOverviewControl")
        implicitWidth: 460
        implicitHeight: aboutColumn.implicitHeight + Theme.spacingL * 2
        minimumSize: Qt.size(400, 400)
        color: Theme.surfaceContainer
        visible: false

        ColumnLayout {
            id: aboutColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingS
                spacing: Theme.spacingS

                BrandMark {
                    Layout.alignment: Qt.AlignHCenter
                    markSize: 76
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacingS

                    StyledText {
                        text: win.t("app.title", "AI Usage Control")
                        font.pixelSize: Theme.fontSizeLarge + 2
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    VersionPill {
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: win.t("about.description", "AI quota, billing, authentication and local usage telemetry for DankMaterialShell.")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            // Developer card
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 64
                radius: Theme.cornerRadius + 4
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.14)

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM

                    Rectangle {
                        id: avatarFrame
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 20
                        color: Theme.withAlpha(Theme.primary, 0.16)
                        clip: true

                        Image {
                            id: avatar
                            anchors.fill: parent
                            source: "https://avatars.githubusercontent.com/u/69475128?v=4&s=80"
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: avatarMask
                            }
                        }

                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        DankIcon {
                            anchors.centerIn: parent
                            visible: avatar.status !== Image.Ready
                            name: "person"
                            size: 20
                            color: Theme.primary
                        }
                    }

                    Column {
                        anchors.left: avatarFrame.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: githubButton.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        StyledText {
                            text: "Bernardo Pinto Gomes"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                        }

                        StyledText {
                            text: "@bernardopg · " + win.t("about.developer", "Developer")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }

                    HeaderAction {
                        id: githubButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        position: "single"
                        iconName: "open_in_new"
                        label: "GitHub"
                        onTriggered: Qt.openUrlExternally("https://github.com/bernardopg")
                    }
                }
            }

            StyledText {
                text: win.t("about.support", "Support the project").toUpperCase()
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 2
                font.weight: Font.DemiBold
                font.letterSpacing: 1.0
            }

            AboutLink {
                iconName: "favorite"
                accent: Theme.error
                label: "GitHub Sponsors"
                url: "https://github.com/sponsors/bernardopg"
            }

            AboutLink {
                iconName: "coffee"
                accent: Theme.warning
                label: "Ko-fi"
                url: "https://ko-fi.com/bernardopg"
            }

            AboutLink {
                iconName: "local_cafe"
                accent: Theme.warning
                label: "Buy Me a Coffee"
                url: "https://buymeacoffee.com/wctwom9emu"
            }

            AboutLink {
                iconName: "thumb_up"
                label: win.t("header.upvote", "Upvote on the DankLinux plugin registry")
                url: win.registryUrl
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingXS
                horizontalAlignment: Text.AlignHCenter
                text: win.t("about.license", "MIT License · made with care for the Dank community")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall - 2
            }
        }
    }
}

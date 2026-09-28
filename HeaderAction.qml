import QtQuick
import qs.Common
import qs.Widgets

// Icon-only popout header button. Segments of a capsule get rounded outer
// corners and tight inner ones; hover morphs the segment into a full pill.
Rectangle {
    id: action

    required property string iconName
    required property string label
    property string position: "middle" // first | middle | last | single
    property color accent: Theme.primary
    property bool actionEnabled: true
    property bool spinning: false
    property real hoverRotation: 0
    // Resting icon rotation (e.g. an expand chevron); hover adds on top.
    property real iconRotation: 0
    // Toggled-on state (pinned, expanded): keeps the accent tint at rest.
    property bool active: false
    readonly property bool hovered: actionMouse.containsMouse

    signal triggered

    readonly property real _outer: hovered || spinning ? height / 2 : Theme.cornerRadius
    readonly property real _inner: hovered || spinning ? height / 2 : 4

    width: 36
    height: 36
    topLeftRadius: position === "first" || position === "single" ? _outer : _inner
    bottomLeftRadius: topLeftRadius
    topRightRadius: position === "last" || position === "single" ? _outer : _inner
    bottomRightRadius: topRightRadius
    color: hovered ? Theme.withAlpha(accent, 0.16) : (active ? Theme.withAlpha(accent, 0.1) : Theme.withAlpha(Theme.surfaceText, 0.05))
    border.width: 1
    border.color: Theme.withAlpha(hovered || active ? accent : Theme.surfaceText, hovered ? 0.34 : (active ? 0.26 : 0.1))
    opacity: actionEnabled || spinning ? 1 : 0.5
    scale: actionMouse.pressed ? 0.92 : (hovered ? 1.05 : 1.0)

    Accessible.role: Accessible.Button
    Accessible.name: label

    Behavior on topLeftRadius {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutExpo
        }
    }
    Behavior on topRightRadius {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutExpo
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: 160
        }
    }
    Behavior on border.color {
        ColorAnimation {
            duration: 160
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutBack
        }
    }

    DankRipple {
        id: actionRipple
        anchors.fill: parent
        cornerRadius: parent.topLeftRadius
        rippleColor: action.accent
    }

    DankIcon {
        anchors.centerIn: parent
        name: action.iconName
        size: 18
        filled: action.active || (action.hovered && action.iconName === "favorite")
        color: action.hovered || action.active ? action.accent : Theme.surfaceText
        rotation: action.spinning ? 0 : action.iconRotation + (action.hovered ? action.hoverRotation : 0)

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
        Behavior on rotation {
            enabled: !action.spinning
            NumberAnimation {
                duration: 360
                easing.type: Easing.OutBack
            }
        }

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: action.spinning
        }
    }

    MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: action.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: mouse => {
            if (action.actionEnabled)
                actionRipple.trigger(mouse.x, mouse.y);
        }
        onClicked: {
            if (action.actionEnabled)
                action.triggered();
        }
    }
}

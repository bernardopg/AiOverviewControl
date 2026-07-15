import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Widgets

Item {
    id: root

    property string providerId: ""
    property string fallbackIcon: "monitoring"
    property color tintColor: Theme.surfaceText
    property int logoSize: 20

    readonly property string canonicalId: {
        const aliases = {
            agy: "antigravity",
            moonshot: "kimi",
            zhipu: "glm",
            dashscope: "qwen",
            alibaba: "qwen",
            nim: "nvidia",
            vertex: "vertexai",
            ark: "byteplus",
            modelark: "byteplus",
            grok: "xai"
        };
        const normalized = String(providerId || "").trim().toLowerCase();
        return aliases[normalized] || normalized;
    }
    readonly property string logoExtension: canonicalId === "byteplus" ? ".png" : ".svg"
    readonly property url logoSource: canonicalId.length > 0
        ? Qt.resolvedUrl("assets/provider-logos/" + canonicalId + logoExtension)
        : ""
    readonly property bool logoReady: logoImage.status === Image.Ready

    implicitWidth: logoSize
    implicitHeight: logoSize
    width: logoSize
    height: logoSize

    Image {
        id: logoImage
        anchors.centerIn: parent
        width: root.logoSize
        height: root.logoSize
        source: root.logoSource
        sourceSize: Qt.size(root.logoSize * 2, root.logoSize * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true

        // Applying the colorization to the image layer keeps the original
        // transparent SVG silhouette; do not use it as a sibling effect
        // source, which is opaque with this renderer.
        layer.enabled: true
        layer.effect: MultiEffect {
            brightness: 1.0
            colorization: 1.0
            colorizationColor: root.tintColor
        }
    }

    DankIcon {
        anchors.centerIn: parent
        visible: root.logoSource.toString().length === 0 || logoImage.status === Image.Error
        name: root.fallbackIcon
        size: root.logoSize
        color: root.tintColor
    }
}
